import Testing
import Foundation
@testable import UniversalAssistant

@MainActor private final class RouteLocationStub: CurrentLocationResolving {
    let value: ValidatedLocation
    init(_ value: ValidatedLocation) { self.value = value }
    func resolveCurrent(for purpose: LocationPurpose) async throws -> ValidatedLocation { value }
}
private actor RouteGeocoderStub: ManualLocationGeocoding {
    let sample: LocationSample
    init(_ sample: LocationSample) { self.sample = sample }
    func resolve(_ label: String) async throws -> LocationSample { .init(latitude: sample.latitude, longitude: sample.longitude, horizontalAccuracy: 0, timestamp: .now, speed: -1, course: -1, source: .manual) }
}
private struct RoutePlaceProviderStub: PlaceProvider {
    let providerID = "places.fixture"
    let places: [Place]
    func search(_ query: PlaceQuery) async throws -> [Place] { places }
}
private struct ReverseLocationStub: ReverseLocationGeocoding {
    let value: String
    func address(for location: ValidatedLocation) async throws -> String { value }
}
private struct RouteProviderStub: RouteProvider {
    let providerID = "routes.fixture"
    func route(_ request: RouteRequest) async throws -> RouteResult {
        let baseline = request.origin.name == "origin" && request.destination.name == "Kyiv"
        let seconds: TimeInterval = baseline ? 600 : 360
        let meters: Double = baseline ? 5000 : 2800
        return .init(distanceMeters: meters, expectedTravelTime: seconds, steps: [], source: providerID, timestamp: .now)
    }
}

@Suite("Production route-aware search")
@MainActor
struct ProductionRouteAwareSearchTests {
    let now = Date(timeIntervalSince1970: 1000)
    func location(_ lat: Double, _ lon: Double, date: Date? = nil) -> ValidatedLocation {
        .init(sample: .init(latitude: lat, longitude: lon, horizontalAccuracy: 5, timestamp: date ?? now, speed: 0, course: 0, source: .device), quality: .precise, isSafeForLocationActions: true, manualLabel: nil)
    }
    @Test func routeSetReplacementExpiryAndReset() {
        let store = CurrentContextStore()
        store.replaceRoute(origin: location(50, 30), destination: location(51, 31), destinationName: "First", now: now, lifetime: 60)
        #expect(store.freshRoute(at: now)?.1.destination.displayName == "First")
        store.replaceRoute(origin: location(50, 30), destination: location(52, 32), destinationName: "Second", now: now.addingTimeInterval(1), lifetime: 60)
        #expect(store.freshRoute(at: now.addingTimeInterval(1))?.1.destination.displayName == "Second")
        #expect(store.freshRoute(at: now.addingTimeInterval(62)) == nil)
        store.replaceRoute(origin: location(50, 30), destination: location(51, 31), destinationName: "Again", now: now, lifetime: 60)
        store.reset(); #expect(store.freshRoute(at: now) == nil)
    }
    @Test func missingAndStaleRouteRejectTruthfully() async {
        let executor = executor(context: CurrentContextStore())
        let command = StructuredCommand(originalText: "Кавярня по дорозі", normalizedText: "кавярня по дорозі", language: .uk, intent: .routeAwareSearch)
        await #expect(throws: CanonicalCapabilityExecutionError.missingParameter("active_route_context")) { try await executor.execute(command) }
    }
    @Test func navigationSeedsContextAndStillReturnsMapsHandoff() async throws {
        let context = CurrentContextStore(); let executor = executor(context: context)
        let command = StructuredCommand(originalText: "Маршрут до Києва", normalizedText: "маршрут до києва", language: .uk, intent: .navigation, entities: ["destination":"Kyiv"])
        guard case let .handoff(value) = try await executor.execute(command) else { Issue.record("Expected Maps handoff"); return }
        #expect(value.kind == .navigation); #expect(context.freshRoute()?.1.destination.displayName == "Kyiv")
    }
    @Test func currentLocationAddressAndTravelTimeStayOnPublicProductionBoundaries() async throws {
        let parser = LocalCommandEngine(), context = CurrentContextStore(), value = executor(context: context)
        let locationCommand = parser.parse("Де я зараз?")
        #expect(locationCommand.intent == .deviceAction)
        guard case let .result(locationResult) = try await value.execute(locationCommand) else { Issue.record("Expected location result"); return }
        #expect(locationResult.facts.first?.source == "CoreLocation")

        let addressCommand = parser.parse("Покажи мою поточну адресу")
        #expect(addressCommand.entities["system_action"] == "current_address")
        guard case let .result(addressResult) = try await value.execute(addressCommand) else { Issue.record("Expected address result"); return }
        #expect(addressResult.primaryAnswer == "Fixture Address")

        let travelCommand = parser.parse("Скільки їхати до нового вокзалу?")
        #expect(travelCommand.entities["destination"] == "нового вокзалу")
        guard case let .result(travelResult) = try await value.execute(travelCommand) else { Issue.record("Expected travel result"); return }
        #expect(travelResult.primaryAnswer == "Приблизно 6 хв")
        #expect(context.freshRoute()?.1.destination.displayName == "нового вокзалу")
    }

    @Test func freshRouteInvokesDetourEngineAndReturnsTypedMapsAction() async throws {
        let context = CurrentContextStore(); context.replaceRoute(origin: location(50, 30), destination: location(51, 31), destinationName: "Kyiv")
        let command = StructuredCommand(originalText: "Кавярня по дорозі", normalizedText: "кавярня по дорозі", language: .uk, intent: .routeAwareSearch)
        guard case let .result(result) = try await executor(context: context).execute(command) else { Issue.record("Expected route-aware result"); return }
        #expect(result.facts.first?.label == "Cafe"); #expect(result.facts.first?.value?.contains("хв") == true)
        #expect(result.actions.first?.destination?.scheme == "https")
    }
    func executor(context: CurrentContextStore) -> ProductionCanonicalCapabilityExecutor {
        let origin = location(50, 30), destination = location(51, 31)
        let place = Place(id: "cafe", providerID: "1", name: "Cafe", category: .cafe, latitude: 50.5, longitude: 30.5, source: "fixture", timestamp: .now, verification: .providerReturned)
        return .init(locationResolver: .init(geocoder: RouteGeocoderStub(destination.sample)), placeSearch: .init(providers: [RoutePlaceProviderStub(places: [place])]), currentLocation: RouteLocationStub(origin), reverseLocation: ReverseLocationStub(value: "Fixture Address"), currentContext: context, routeProvider: RouteProviderStub(), personalSearchSources: [])
    }
}
