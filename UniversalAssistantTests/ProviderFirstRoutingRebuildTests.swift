import Foundation
import Testing
@testable import UniversalAssistant

private struct ProviderFirstPlaceSource: PlaceProvider {
    let providerID = "provider-first-fixture"
    let values: [Place]
    func search(_ query: PlaceQuery) async throws -> [Place] { values }
}

@MainActor
private final class ProviderFirstLocationSource: CurrentLocationResolving {
    let value: ValidatedLocation
    init(_ value: ValidatedLocation) { self.value = value }
    func resolveCurrent(for purpose: LocationPurpose) async throws -> ValidatedLocation { value }
}

private struct ProviderFirstContactSource: ContactResolving {
    let candidate: ContactCandidate
    func authorizationState() async -> ContactAuthorizationState { .authorized }
    func requestAccessIfNeeded() async throws {}
    func resolve(name: String) async throws -> ContactResolution { .resolved(candidate) }
    func resolve(exactIdentifier identifier: String) async throws -> ContactResolution { .resolved(candidate) }
    func contextualVocabulary(limit: Int) async -> [String] { [] }
}

@MainActor
private final class ProviderFirstHandoffExecutor: CanonicalCapabilityExecuting {
    let destination: URL
    init(destination: URL) { self.destination = destination }
    func execute(_ command: StructuredCommand) async throws -> CapabilityExecutionOutcome {
        .handoff(.init(query: command.originalText, destination: destination, kind: .provider))
    }
}

@Suite("Provider-first and Apple-first canonical routing rebuild", .serialized)
@MainActor
struct ProviderFirstRoutingRebuildTests {
    private let policy = CanonicalRoutingPolicy()

    @Test func everyCanonicalIntentHasOneDocumentableRoutingDecision() {
        #expect(CommandIntent.allCases.count == 57)
        for intent in CommandIntent.allCases {
            let decision = policy.decide(command(intent, [:]))
            #expect(!decision.reason.isEmpty, "Missing policy reason for \(intent)")
        }
    }

    @Test func everyOwnerPriorityLaneHasOneDeterministicDecision() {
        let cases: [(StructuredCommand, CanonicalRoutingLane, String?)] = [
            (command(.contactLookup, ["contact": "Олена"]), .appleSystem, nil),
            (command(.productSearch, ["provider": "eBay", "product": "Seiko"]), .explicitProvider, "market.ebay"),
            (command(.fashionDiscovery, ["brand": "Adidas", "product": "кросівки"]), .officialBrand, "brand.adidas"),
            (command(.placeSearch, ["query": "кава", "near_current_location": "true"]), .localDiscovery, "google.maps.url"),
            (command(.hotelSearch, ["location": "Львів"]), .accommodation, "lodging.booking"),
            (command(.reservation, ["party_size": "2"]), .restaurantReservation, nil),
            (command(.productSearch, ["provider_domain": "jobs", "query": "водій Київ"]), .jobs, "jobs.workua"),
            (command(.ticketSearch, ["location": "Полтава"]), .events, "events.karabas"),
            (command(.parcelTrack, ["provider": "Meest", "query": "CV123"]), .explicitProvider, "parcel.meest"),
            (command(.webSearch, ["query": "офіційна специфікація USB-C"]), .informationalWeb, nil)
        ]
        for (input, lane, providerID) in cases {
            let decision = policy.decide(input)
            #expect(decision.lane == lane)
            #expect(decision.providerID == providerID)
            #expect(decision.allowsMultipleResults == false)
        }
    }

    @Test func productionParserFeedsGoldenJourneysIntoTheSamePolicy() {
        let parser = LanguageUnderstandingBlock()
        let cases: [(String, CanonicalRoutingLane, String?)] = [
            ("Хочу кави поруч", .localDiscovery, "google.maps.url"),
            ("Знайди найближчу аптеку", .localDiscovery, "google.maps.url"),
            ("Де поруч купити кросівки", .localDiscovery, "google.maps.url"),
            ("Покажи нову колекцію Baldinini", .officialBrand, "brand.baldinini"),
            ("Кросівки Adidas", .officialBrand, "brand.adidas"),
            ("Знайди Seiko на eBay", .explicitProvider, "market.ebay"),
            ("Знайди мультиметр на AliExpress", .explicitProvider, "market.aliexpress"),
            ("Знайди готель у Львові", .accommodation, "lodging.booking"),
            ("Знайди грузинський ресторан поруч", .localDiscovery, "google.maps.url"),
            ("Знайди концерт у Полтаві", .events, "events.karabas"),
            ("Знайди роботу водієм у Києві від 50 000", .jobs, "jobs.workua"),
            ("Покажи картку Івана", .appleSystem, nil),
            ("Напиши Івану на пошту", .appleSystem, nil)
        ]
        for (text, lane, providerID) in cases {
            let command = parser.parse(text)
            let decision = policy.decide(command)
            #expect(decision.lane == lane, "Unexpected lane for: \(text); intent=\(command.intent); entities=\(command.entities); brand=\(String(describing: command.constraints.brand))")
            #expect(decision.providerID == providerID, "Unexpected provider for: \(text)")
            #expect(decision.allowsMultipleResults == false)
        }
    }

    @Test func registryMatchingRecoversUnseenNamedProviderWithoutPhraseRules() {
        let input = StructuredCommand(
            originalText: "Покажи годинник на eBay",
            normalizedText: "покажи годинник на ebay",
            language: .uk,
            intent: .productSearch,
            entities: ["product": "годинник"]
        )
        let decision = policy.decide(input)
        #expect(decision.lane == .explicitProvider)
        #expect(decision.providerID == "market.ebay")
    }

    @Test func providerNamesCannotCaptureInformationalOrPersonalTypedRoles() {
        let information = StructuredCommand(
            originalText: "Розкажи про eBay як компанію",
            normalizedText: "розкажи про ebay як компанію",
            language: .uk,
            intent: .webSearch,
            entities: ["query": "eBay як компанія"]
        )
        #expect(policy.decide(information).lane == .informationalWeb)

        let personal = StructuredCommand(
            originalText: "Подзвони контакту Amazon",
            normalizedText: "подзвони контакту amazon",
            language: .uk,
            intent: .contactCall,
            entities: ["contact": "Amazon"]
        )
        #expect(policy.decide(personal).lane == .appleSystem)
    }

    @Test func explicitMarketplaceOpensOnlyThatProviderAndPreservesConstraints() async throws {
        let input = StructuredCommand(
            originalText: "Знайди Seiko на eBay розмір 42 до 900 євро з доставкою в Україну",
            normalizedText: "знайди seiko на ebay розмір 42 до 900 євро з доставкою в україну",
            language: .uk,
            intent: .productSearch,
            entities: ["provider": "eBay", "product": "Seiko", "location": "Україна", "delivery_constraint": "delivery"],
            constraints: .init(maximumPrice: 900, currency: "EUR", size: "42", brand: "Seiko")
        )
        guard case let .result(result) = try await executor().execute(input),
              let destination = result.actions.first?.destination else {
            Issue.record("Explicit provider must produce one exact source card")
            return
        }
        #expect(destination.host == "www.ebay.com")
        let query = URLComponents(url: destination, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == "_nkw" })?.value ?? ""
        #expect(query.localizedCaseInsensitiveContains("Seiko"))
        #expect(query.contains("42"))
        #expect(query.contains("900"))
        #expect(query.localizedCaseInsensitiveContains("Україна"))
    }

    @Test func officialBrandAndBookingUseExactOfficialDestinations() async throws {
        let brand = command(.fashionDiscovery, ["brand": "Baldinini", "product": "нова колекція"])
        guard case let .result(brandResult) = try await executor().execute(brand),
              let brandDestination = brandResult.actions.first?.destination else {
            Issue.record("Brand must use its official route"); return
        }
        #expect(brandDestination.host == "www.baldinini-shop.com")
        #expect(brandDestination.path.contains("search"))

        let hotel = command(.hotelSearch, [
            "location": "Львів", "checkin": "2026-10-10", "checkout": "2026-10-12",
            "guest_count": "2", "room_count": "1"
        ])
        guard case let .handoff(booking) = try await executor().execute(hotel) else {
            Issue.record("Accommodation must use Booking.com"); return
        }
        let components = URLComponents(url: booking.destination, resolvingAgainstBaseURL: false)
        #expect(booking.destination.host == "www.booking.com")
        #expect(components?.queryItems?.contains(.init(name: "ss", value: "Львів")) == true)
        #expect(components?.queryItems?.contains(.init(name: "checkin", value: "2026-10-10")) == true)
        #expect(components?.queryItems?.contains(.init(name: "checkout", value: "2026-10-12")) == true)
    }

    @Test func karabasPreservesVerifiedCityAndNeverDefaultsToKyiv() async throws {
        for (city, host, query, path) in [
            ("Полтава", "poltava.karabas.com", "концерт", "/concerts"),
            ("Черкаси", "cherkasy.karabas.com", "дитяча вистава", "/kids"),
            ("Львів", "lviv.karabas.com", "театр", "/theatres")
        ] {
            let input = command(.ticketSearch, ["provider_domain": "tickets", "location": city, "query": query])
            guard case let .handoff(value) = try await executor().execute(input) else {
                Issue.record("Expected city-scoped KARABAS route"); continue
            }
            #expect(value.destination.host == host)
            #expect(value.destination.path == path)
            #expect(value.destination.host != "kyiv.karabas.com")
        }
        await #expect(throws: CanonicalCapabilityExecutionError.externalProviderRequired("ticketSearch")) {
            try await executor().execute(command(.ticketSearch, ["provider_domain": "tickets", "location": "Кременчук", "query": "подія"]))
        }
    }

    @Test func unnamedNearbyRequestReturnsOneExactGoogleMapsDestination() async throws {
        let location = ValidatedLocation(
            sample: .init(latitude: 50.4501, longitude: 30.5234, horizontalAccuracy: 5,
                          timestamp: .now, speed: 0, course: 0, source: .device),
            quality: .precise, isSafeForLocationActions: true, manualLabel: nil
        )
        let places = [
            Place(id: "far", providerID: "mapkit-far", name: "Далека кава", category: .cafe,
                  latitude: 50.4900, longitude: 30.5900, source: "MapKit", timestamp: .now, verification: .providerReturned),
            Place(id: "near", providerID: "mapkit-near", name: "Найближча кава", category: .cafe,
                  latitude: 50.4502, longitude: 30.5235, source: "MapKit", timestamp: .now, verification: .providerReturned)
        ]
        let executor = ProductionCanonicalCapabilityExecutor(
            placeSearch: .init(providers: [ProviderFirstPlaceSource(values: places)]),
            currentLocation: ProviderFirstLocationSource(location), personalSearchSources: []
        )
        let input = command(.placeSearch, ["query": "кава", "near_current_location": "true"])
        guard case let .placeResults(values) = try await executor.execute(input),
              let first = values.first else {
            Issue.record("Nearby discovery must return internal place results"); return
        }
        #expect(first.id == "near")
    }

    @Test func contactLookupUsesTheOfficialExistingContactCardBoundary() async throws {
        let candidate = ContactCandidate(identifier: "contact-identifier", displayName: "Іван Петренко",
                                         phoneNumbers: ["+380671234567"], emailAddresses: ["ivan@example.com"])
        let executor = ProductionCanonicalCapabilityExecutor(
            contacts: ProviderFirstContactSource(candidate: candidate), personalSearchSources: []
        )
        guard case let .presentation(value) = try await executor.execute(command(.contactLookup, ["contact": "Іван Петренко"])) else {
            Issue.record("Contact lookup must present ContactsUI"); return
        }
        #expect(value == .contactCard(identifier: "contact-identifier"))
    }

    @Test func connectionsAreOfficialBoundariesAndNeverCollectProviderPasswords() {
        #expect(ConnectableServiceRegistry.records.map(\.id) == ["google", "ebay", "nova-poshta", "meest", "ukrposhta"])
        #expect(ConnectableServiceRegistry.records.allSatisfy { !$0.acceptsThirdPartyPassword })
        #expect(ConnectableServiceRegistry.records.allSatisfy { $0.status != .available })
    }

    @Test func genericWebFallbackIsAnExactQueryAndNeverAHomepage() throws {
        let input = LocalCommandEngine().parse("Пошукай в інтернеті офіційну специфікацію USB-C")
        let url = try ControlledWebSearchHandoff().destination(for: input, structuredCapabilityAvailable: false)
        #expect(url.host == "www.google.com")
        #expect(url.path == "/search")
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "офіційну специфікацію USB-C")
    }

    @Test func rejectedIOSOpenNeverBecomesVisibleOrTerminalSuccess() async {
        var openCount = 0
        let model = AssistantViewModel(
            capabilityExecutor: ProviderFirstHandoffExecutor(destination: URL(string: "https://www.ebay.com/sch/i.html?_nkw=Seiko")!),
            compactResultDuration: .seconds(60),
            systemHandoffOpenResult: { _ in
                openCount += 1
                return false
            }
        )
        model.input = "Знайди Seiko на eBay"
        model.submit()
        for _ in 0..<100 {
            if case .failure = model.resultState { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(openCount == 1)
        #expect({ if case .failure = model.resultState { return true }; return false }())
    }

    @Test func acceptedIOSOpenOccursExactlyOnceWithoutAnIntermediateProviderButton() async {
        var destinations: [URL] = []
        let exact = URL(string: "https://www.ebay.com/sch/i.html?_nkw=Seiko")!
        let model = AssistantViewModel(
            capabilityExecutor: ProviderFirstHandoffExecutor(destination: exact),
            compactResultDuration: .seconds(60),
            systemHandoffOpenResult: { destination in
                destinations.append(destination)
                return true
            }
        )
        model.input = "Знайди Seiko на eBay"
        model.submit()
        for _ in 0..<100 {
            if destinations.count == 1, model.resultState == .idle { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(destinations == [exact])
        #expect(model.resultState == .idle)
    }

    private func executor() -> ProductionCanonicalCapabilityExecutor {
        ProductionCanonicalCapabilityExecutor(personalSearchSources: [])
    }

    private func command(_ intent: CommandIntent, _ entities: [String: String]) -> StructuredCommand {
        let text = entities["query"] ?? entities["product"] ?? entities["location"] ?? "canonical request"
        return .init(originalText: text, normalizedText: text.lowercased(), language: .uk, intent: intent, entities: entities)
    }
}
