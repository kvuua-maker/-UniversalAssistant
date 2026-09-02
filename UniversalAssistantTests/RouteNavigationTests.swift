import Foundation
import Testing
@testable import UniversalAssistant

private struct FixtureRouteProvider: RouteProvider {
    let providerID = "fixture"
    func route(_ request: RouteRequest) -> RouteResult {
        let isBaseline = request.origin.name == "origin" && request.destination.name == "destination"
        let time: TimeInterval = isBaseline ? 600 : (request.destination.name == "Cafe" ? 300 : 420)
        let distance: Double = isBaseline ? 5_000 : (request.destination.name == "Cafe" ? 2_000 : 4_000)
        return .init(distanceMeters: distance, expectedTravelTime: time, steps: [], source: providerID, timestamp: .now)
    }
}

private actor MemoryNavigationPreferences: NavigationPreferencePersisting {
    var value: NavigationProvider?
    func load() -> NavigationProvider? { value }
    func save(_ provider: NavigationProvider) { value = provider }
}

struct RouteNavigationTests {
    @Test func routeAwareSearchUsesActualRouteDurationsForDetour() async throws {
        let place = Place(id: "cafe", providerID: "cafe", name: "Cafe", category: .cafe, latitude: 50.46, longitude: 30.53, source: "test", timestamp: .now, verification: .providerReturned)
        let engine = RouteAwareSearchEngine(routeProvider: FixtureRouteProvider())
        let result = try await engine.evaluate(
            origin: .init(latitude: 50.45, longitude: 30.52, name: "origin"),
            destination: .init(latitude: 50.50, longitude: 30.60, name: "destination"),
            candidates: [place], mode: .driving
        )
        #expect(result.first?.detourSeconds == 120)
        #expect(result.first?.detourMeters == 1_000)
    }

    @Test("Exact navigation URLs", arguments: NavigationProvider.allCases)
    func exactHandoff(provider: NavigationProvider) throws {
        let url = try NavigationHandoff().url(provider: provider, destination: .init(latitude: 50.4501, longitude: 30.5234, name: "Target"), mode: .walking)
        let values = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(values.contains { $0.value?.contains("50.4501,30.5234") == true })
        if provider == .googleMaps { #expect(values.contains(.init(name: "api", value: "1"))) }
        if provider == .waze { #expect(values.contains(.init(name: "navigate", value: "yes"))) }
    }

    @Test func invalidDestinationNeverOpensProviderHomepage() {
        #expect(throws: RouteError.invalidCoordinate) {
            try NavigationHandoff().url(provider: .appleMaps, destination: .init(latitude: 200, longitude: 0), mode: .driving)
        }
    }

    @Test func defaultMapPersistsAndRestores() async throws {
        let persistence = MemoryNavigationPreferences()
        let first = NavigationPreferences(persistence: persistence)
        try await first.setDefault(.waze)
        let restored = NavigationPreferences(persistence: persistence)
        try await restored.restore()
        #expect(await restored.defaultProvider == .waze)
    }

    @Test func initialWalkingGuidanceUsesOnlyVerifiedFirstRouteStep() {
        let time = Date(timeIntervalSince1970: 100)
        let route = RouteResult(distanceMeters: 500, expectedTravelTime: 420,
                                steps: ["", "  Turn left onto Main Street  ", "Continue"],
                                source: "verified-route", timestamp: time)
        #expect(InitialWalkingGuidanceComposer().compose(from: route, mode: .walking) ==
                .init(instruction: "Turn left onto Main Street", source: "verified-route", timestamp: time))
        #expect(InitialWalkingGuidanceComposer().compose(from: route, mode: .driving) == nil)
        #expect(InitialWalkingGuidanceComposer().compose(
            from: .init(distanceMeters: 500, expectedTravelTime: 420, steps: [], source: "verified-route", timestamp: time),
            mode: .walking
        ) == nil)
    }
}
