import Foundation

struct DepartureBuffers: Equatable, Sendable {
    var traffic: TimeInterval
    var parking: TimeInterval
    var walking: TimeInterval
    var safety: TimeInterval

    var total: TimeInterval { traffic + parking + walking + safety }
    var isValid: Bool { [traffic, parking, walking, safety].allSatisfy { $0 >= 0 } }
}

struct SmartDepartureRequest: Equatable, Sendable {
    let origin: String
    let destination: String
    let arrivalDeadline: Date
    let route: TransportOption
    let buffers: DepartureBuffers
}

struct DepartureRecommendation: Equatable, Sendable {
    let origin: String
    let destination: String
    let departureAt: Date
    let arrivalDeadline: Date
    let routeID: String
    let routeSource: String
    let travelTime: TimeInterval
    let buffers: DepartureBuffers
}

enum SmartDepartureError: Error, Equatable { case invalidRequest, unverifiedRoute }

struct SmartDepartureEngine: Sendable {
    let maximumEvidenceAge: TimeInterval
    let meaningfulChange: TimeInterval

    init(maximumEvidenceAge: TimeInterval = 300, meaningfulChange: TimeInterval = 120) {
        self.maximumEvidenceAge = maximumEvidenceAge
        self.meaningfulChange = meaningfulChange
    }

    func recommend(_ request: SmartDepartureRequest, now: Date = .now) throws -> DepartureRecommendation {
        guard !request.origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !request.destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              request.arrivalDeadline > now, request.buffers.isValid,
              maximumEvidenceAge > 0, meaningfulChange >= 0 else { throw SmartDepartureError.invalidRequest }
        guard let duration = request.route.durationSeconds, duration >= 0,
              !request.route.evidence.source.isEmpty,
              request.route.isFresh(now: now, maximumAge: maximumEvidenceAge),
              request.route.availability != .unavailable else { throw SmartDepartureError.unverifiedRoute }
        return .init(
            origin: request.origin, destination: request.destination,
            departureAt: request.arrivalDeadline.addingTimeInterval(-(duration + request.buffers.total)),
            arrivalDeadline: request.arrivalDeadline, routeID: request.route.id,
            routeSource: request.route.evidence.source, travelTime: duration, buffers: request.buffers
        )
    }

    func meaningfulUpdate(
        previous: DepartureRecommendation,
        request: SmartDepartureRequest,
        now: Date = .now
    ) throws -> DepartureRecommendation? {
        let current = try recommend(request, now: now)
        guard current.origin == previous.origin, current.destination == previous.destination,
              current.arrivalDeadline == previous.arrivalDeadline else { throw SmartDepartureError.invalidRequest }
        return abs(current.departureAt.timeIntervalSince(previous.departureAt)) >= meaningfulChange ? current : nil
    }
}
