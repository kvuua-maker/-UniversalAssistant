@preconcurrency import MapKit
import Foundation

enum TravelMode: String, Codable, Sendable { case driving, walking, transit }
struct RoutePoint: Equatable, Codable, Sendable { let latitude: Double; let longitude: Double; var name: String? }
struct RouteRequest: Equatable, Sendable { let origin: RoutePoint; let destination: RoutePoint; let mode: TravelMode }
struct RouteResult: Equatable, Sendable {
    let distanceMeters: Double
    let expectedTravelTime: TimeInterval
    let steps: [String]
    let source: String
    let timestamp: Date
}

struct InitialWalkingGuidance: Equatable, Sendable {
    let instruction: String
    let source: String
    let timestamp: Date
}

struct InitialWalkingGuidanceComposer: Sendable {
    func compose(from route: RouteResult, mode: TravelMode) -> InitialWalkingGuidance? {
        guard mode == .walking,
              route.distanceMeters > 0,
              route.expectedTravelTime > 0,
              let first = route.steps.lazy.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                .first(where: { !$0.isEmpty }) else { return nil }
        return .init(instruction: first, source: route.source, timestamp: route.timestamp)
    }
}
protocol RouteProvider: Sendable {
    var providerID: String { get }
    func route(_ request: RouteRequest) async throws -> RouteResult
}

struct MapKitRouteProvider: RouteProvider {
    let providerID = "apple-mapkit-directions"
    func route(_ input: RouteRequest) async throws -> RouteResult {
        let request = MKDirections.Request()
        request.source = Self.mapItem(input.origin)
        request.destination = Self.mapItem(input.destination)
        request.transportType = switch input.mode { case .driving: .automobile; case .walking: .walking; case .transit: .transit }
        request.requestsAlternateRoutes = false
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.min(by: { $0.expectedTravelTime < $1.expectedTravelTime }) else { throw RouteError.noRoute }
        return .init(
            distanceMeters: route.distance, expectedTravelTime: route.expectedTravelTime,
            steps: route.steps.map(\.instructions).filter { !$0.isEmpty }, source: providerID, timestamp: .now
        )
    }
    private static func mapItem(_ point: RoutePoint) -> MKMapItem {
        let coordinate = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
        // MKMapItem(location:address:) is not declared by the build SDK; the
        // placemark initializer is the portable path.
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = point.name
        return item
    }
}

enum RouteError: Error, Equatable { case noRoute, invalidCoordinate }
struct RouteAwarePlace: Equatable, Sendable { let place: Place; let detourSeconds: TimeInterval; let detourMeters: Double }

struct RouteAwareSearchEngine: Sendable {
    let routeProvider: any RouteProvider
    var maximumCandidates = 8

    func evaluate(origin: RoutePoint, destination: RoutePoint, candidates: [Place], mode: TravelMode) async throws -> [RouteAwarePlace] {
        let baseline = try await routeProvider.route(.init(origin: origin, destination: destination, mode: mode))
        return await withTaskGroup(of: RouteAwarePlace?.self) { group in
            for place in candidates.prefix(maximumCandidates) {
                group.addTask {
                    let point = RoutePoint(latitude: place.latitude, longitude: place.longitude, name: place.name)
                    do {
                        async let first = routeProvider.route(.init(origin: origin, destination: point, mode: mode))
                        async let second = routeProvider.route(.init(origin: point, destination: destination, mode: mode))
                        let (a, b) = try await (first, second)
                        return .init(
                            place: place,
                            detourSeconds: max(0, a.expectedTravelTime + b.expectedTravelTime - baseline.expectedTravelTime),
                            detourMeters: max(0, a.distanceMeters + b.distanceMeters - baseline.distanceMeters)
                        )
                    } catch { return nil }
                }
            }
            var output: [RouteAwarePlace] = []
            for await value in group { if let value { output.append(value) } }
            return output.sorted { $0.detourSeconds == $1.detourSeconds ? $0.place.id < $1.place.id : $0.detourSeconds < $1.detourSeconds }
        }
    }
}
