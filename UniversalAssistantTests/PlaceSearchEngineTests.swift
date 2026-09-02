import Foundation
import Testing
@testable import UniversalAssistant

private struct FixturePlaceProvider: PlaceProvider {
    let providerID: String
    let values: [Place]
    var delay: Duration = .zero
    var fails = false
    func search(_ query: PlaceQuery) async throws -> [Place] {
        try await Task.sleep(for: delay)
        if fails { throw TestFailure.failed }
        return values
    }
    enum TestFailure: Error { case failed }
}

private struct CoffeeRouteProvider: RouteProvider {
    let providerID = "verified-walking"
    func route(_ request: RouteRequest) async throws -> RouteResult {
        let seconds: TimeInterval = request.destination.name == "Near" ? 180 : 900
        return .init(distanceMeters: seconds, expectedTravelTime: seconds,
                     steps: ["Walk to \(request.destination.name ?? "cafe")"],
                     source: providerID, timestamp: .now)
    }
}

struct PlaceSearchEngineTests {
    private let location = ValidatedLocation(sample: .init(latitude: 50.45, longitude: 30.52, horizontalAccuracy: 10, timestamp: .now, speed: -1, course: -1, source: .device), quality: .good, isSafeForLocationActions: true, manualLabel: nil)
    private func place(_ id: String, source: String, distance: Double) -> Place {
        .init(id: id, providerID: id, name: "Coffee", category: .cafe, latitude: 50.45, longitude: 30.52, distanceMeters: distance, source: source, timestamp: .now, verification: .providerReturned)
    }

    @Test func partialResultsSurviveProviderFailureAndAreRanked() async throws {
        let good = FixturePlaceProvider(providerID: "good", values: [place("far", source: "good", distance: 900), place("near", source: "good", distance: 50)])
        let bad = FixturePlaceProvider(providerID: "bad", values: [], fails: true)
        let result = try await PlaceSearchEngine(providers: [good, bad]).search(.init(text: "Coffee", category: .cafe, location: location))
        #expect(result.places.map(\.id) == ["near", "far"])
        #expect(result.failures == [.init(providerID: "bad", reason: "provider_error")])
    }

    @Test func slowProviderTimesOutWithoutBlockingFastResult() async throws {
        let fast = FixturePlaceProvider(providerID: "fast", values: [place("one", source: "fast", distance: 10)])
        let slow = FixturePlaceProvider(providerID: "slow", values: [], delay: .seconds(1))
        let result = try await PlaceSearchEngine(providers: [fast, slow], timeout: .milliseconds(20)).search(.init(text: "Coffee", category: .cafe, location: location))
        #expect(result.places.count == 1)
        #expect(result.failures == [.init(providerID: "slow", reason: "timeout")])
    }

    @Test func providerFanoutIsBounded() async throws {
        let providers = (0..<6).map { FixturePlaceProvider(providerID: "\($0)", values: [place("\($0)", source: "\($0)", distance: Double($0))]) }
        let result = try await PlaceSearchEngine(providers: providers, maximumProviders: 2).search(.init(text: "Coffee", category: .cafe, location: location))
        #expect(result.places.count == 1) // reliable cross-source duplicates collapse
    }

    @Test func coffeeScenarioRunsValidatedProviderRouteRankingAndExactActionEndToEnd() async throws {
        let candidates = [
            Place(id: "far", providerID: "far", name: "Far", category: .cafe,
                  latitude: 50.47, longitude: 30.55, isOpenNow: true,
                  source: "fixture", timestamp: .now, verification: .providerReturned),
            Place(id: "near", providerID: "near", name: "Near", category: .cafe,
                  latitude: 50.451, longitude: 30.521, isOpenNow: true,
                  source: "fixture", timestamp: .now, verification: .providerReturned)
        ]
        let coordinator = CoffeeScenarioCoordinator(
            places: PlaceSearchEngine(providers: [FixturePlaceProvider(providerID: "fixture", values: candidates)]),
            routes: CoffeeRouteProvider()
        )
        let result = try await coordinator.search(near: location, navigationProvider: .appleMaps)
        #expect(result.places.map(\.id) == ["near", "far"])
        #expect(result.places.first?.travelTimeSeconds == 180)
        #expect(URLComponents(url: result.primaryAction!, resolvingAgainstBaseURL: false)?.queryItems?
            .contains { $0.name == "dirflg" && $0.value == "w" } == true)
    }
}
