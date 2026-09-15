import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Build 40 zero-owner provider completion", .serialized)
@MainActor
struct Build40ZeroOwnerProviderCompletionTests {
    @Test func officialRegistryIsCompleteUniqueAndUsesOnlyOfficialHTTPSDestinations() throws {
        let records = OfficialPublicProviderHandoffRegistry.records
        #expect(records.count == 26)
        #expect(Set(records.map(\.id)).count == records.count)
        #expect(records.filter { $0.domain == .marketplace }.count == 5)
        #expect(records.filter { $0.domain == .grocery }.count == 4)
        #expect(records.filter { $0.domain == .lodging }.count == 2)
        #expect(records.filter { $0.domain == .carRental }.count == 1)
        #expect(records.filter { $0.domain == .events }.count == 1)
        #expect(records.filter { $0.domain == .cinema }.count == 2)
        #expect(records.filter { $0.domain == .jobs }.count == 7)
        #expect(records.filter { $0.domain == .transport }.count == 1)
        #expect(records.filter { $0.domain == .parcel }.count == 3)

        for record in records {
            let destination = try #require(record.destination(query: "wireless headphones 43"))
            #expect(destination.scheme == "https")
            #expect(destination.host?.contains("google") != true)
            #expect(record.officialEvidence.scheme == "https")
            #expect(!record.mechanism.isEmpty)
        }
        #expect(records.first { $0.id == "market.ebay" }?.preservesQuery == true)
        #expect(records.first { $0.id == "lodging.dobovo" }?.preservesQuery == false)
    }

    @Test func exactMarketplaceRoutesPreserveTheBuyerQueryWithoutGenericWeb() throws {
        let expected: [String: (host: String, key: String?)] = [
            "market.amazon": ("www.amazon.com", "k"),
            "market.ebay": ("www.ebay.com", "_nkw"),
            "market.aliexpress": ("www.aliexpress.com", nil),
            "market.temu": ("www.temu.com", "search_key"),
            "market.prom": ("prom.ua", "search_term")
        ]
        for (id, expectation) in expected {
            let record = try #require(OfficialPublicProviderHandoffRegistry.records.first { $0.id == id })
            let destination = try #require(record.destination(query: "portable solar charger"))
            #expect(destination.host == expectation.host)
            if let key = expectation.key {
                let value = URLComponents(url: destination, resolvingAgainstBaseURL: false)?.queryItems?
                    .first(where: { $0.name == key })?.value
                #expect(value == "portable solar charger")
            } else {
                #expect(destination.path.contains("portable-solar-charger"))
            }
        }
    }

    @Test func officialSearchParametersArePreservedForRetailAndJobs() throws {
        let ids = ["retail.silpo", "retail.atb", "retail.fora", "retail.fozzy",
                   "jobs.workua", "jobs.robotaua", "jobs.jobsua", "jobs.djinni",
                   "jobs.dou", "jobs.happymonday"]
        for id in ids {
            let record = try #require(OfficialPublicProviderHandoffRegistry.records.first { $0.id == id })
            let destination = try #require(record.destination(query: "senior product designer remote"))
            let values = URLComponents(url: destination, resolvingAgainstBaseURL: false)?.queryItems?
                .compactMap(\.value) ?? []
            #expect(values.contains("senior product designer remote"))
            #expect(destination.host?.contains("google") != true)
        }
    }

    @Test func providerEntityAndNewProviderFamiliesRemainTyped() {
        let parser = LanguageUnderstandingBlock()
        let marketplace = parser.parse("Порівняй портативні зарядні станції на eBay до 900 євро")
        #expect(marketplace.intent == .productSearch)
        #expect(marketplace.entities["catalog_entity_id"] == "market.ebay")
        #expect(!marketplace.needsClarification)

        let jobs = parser.parse("Підбери вакансії архітектора з віддаленою роботою")
        #expect(jobs.intent == .productSearch)
        #expect(jobs.entities["provider_domain"] == "jobs")
        #expect(!jobs.needsClarification)

        let events = parser.parse("Покажи дитячі фестивалі та циркові вистави")
        #expect(events.intent == .ticketSearch)
        #expect(events.entities["provider_domain"] == "tickets")

        let rail = parser.parse("Знайди розклад потягів між Віднем і Прагою")
        #expect(rail.intent == .ticketSearch)
        #expect(rail.entities["provider_domain"] == "transport_tickets")
    }

    @Test func productionExecutorUsesExactExplicitMarketplaceRoute() async throws {
        let command = StructuredCommand(
            originalText: "Пошукай механічну клавіатуру на eBay",
            normalizedText: "пошукай механічну клавіатуру на ebay",
            language: .uk,
            intent: .productSearch,
            entities: ["provider": "eBay", "product": "механічна клавіатура"]
        )
        guard case let .handoff(handoff) = try await executor().execute(command) else {
            Issue.record("Expected an official provider handoff")
            return
        }
        #expect(handoff.kind == .provider)
        #expect(handoff.destination.host == "www.ebay.com")
        let query = URLComponents(url: handoff.destination, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == "_nkw" })?.value
        #expect(query == "механічна клавіатура")
    }

    @Test func productionPolicySelectsOneProviderAndNeverCreatesAnUnrequestedChooser() async throws {
        let jobs = command(.productSearch, ["provider_domain": "jobs", "query": "qa engineer remote"])
        guard case let .handoff(jobHandoff) = try await executor().execute(jobs) else {
            Issue.record("Expected one Jobs fallback handoff"); return
        }
        #expect(jobHandoff.destination.host == "www.work.ua")

        let hotel = command(.hotelSearch, ["location": "Краків"])
        guard case let .handoff(hotelHandoff) = try await executor().execute(hotel) else {
            Issue.record("Expected Booking handoff"); return
        }
        #expect(hotelHandoff.destination.host == "www.booking.com")

        let event = command(.ticketSearch, ["provider_domain": "tickets", "query": "сімейні події", "location": "Полтава"])
        guard case let .handoff(eventHandoff) = try await executor().execute(event) else {
            Issue.record("Expected city-scoped KARABAS handoff"); return
        }
        #expect(eventHandoff.destination.host == "poltava.karabas.com")

        let parcel = command(.parcelTrack, ["provider_domain": "parcel_tracking", "query": "RR123456789UA"])
        await #expect(throws: CanonicalCapabilityExecutionError.missingParameter("parcel_provider")) {
            try await executor().execute(parcel)
        }

        #expect(CanonicalRoutingPolicy().decide(command(.productSearch, ["product": "туристичний рюкзак"])).lane == .localDiscovery)
        #expect(CanonicalRoutingPolicy().decide(command(.groceryBasket, ["query": "овочі для супу"])).lane == .localDiscovery)
    }

    @Test func carRentalRailAndExplicitParcelUseTheirOfficialConsumerDestinations() async throws {
        let values: [(StructuredCommand, String)] = [
            (command(.serviceSearch, ["provider_domain": "car_rental", "provider": "Getmancar", "location": "Львів"]), "getmancar.com"),
            (command(.ticketSearch, ["provider_domain": "transport_tickets", "query": "Львів Варшава"]), "booking.uz.gov.ua"),
            (command(.parcelTrack, ["provider": "Укрпошта", "query": "міжнародне відправлення"]), "track.ukrposhta.ua")
        ]
        for (input, host) in values {
            guard case let .handoff(handoff) = try await executor().execute(input) else {
                Issue.record("Expected exact official handoff")
                continue
            }
            #expect(handoff.kind == .provider)
            #expect(handoff.destination.host == host)
        }
    }

    @Test func taxiWithoutExistingAuthorizationRemainsTruthfulProviderBoundary() async {
        let input = command(.taxiSearch, ["destination": "музей"])
        await #expect(throws: CanonicalCapabilityExecutionError.externalProviderRequired("taxiSearch")) {
            try await executor().execute(input)
        }
    }

    @Test func officialNBUReferenceRatesCoverUAHWithoutACommercialCredential() async throws {
        let provider = NBUCurrentFXProvider(load: { request in
            let body = #"[{"rate":40,"cc":"USD","exchangedate":"12.09.2026"}]"#.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (body, response)
        }, now: { Date(timeIntervalSince1970: 1_789_171_200) })
        let request = FXConversionRequest(amount: 2, source: "USD", destination: "UAH")
        let result = try await provider.convert(request)
        #expect(result.convertedAmount == 80)
        #expect(result.provider == "National Bank of Ukraine")
    }

    private func executor() -> ProductionCanonicalCapabilityExecutor {
        ProductionCanonicalCapabilityExecutor(personalSearchSources: [])
    }

    private func command(_ intent: CommandIntent, _ entities: [String: String]) -> StructuredCommand {
        StructuredCommand(
            originalText: entities["query"] ?? entities["product"] ?? "provider request",
            normalizedText: entities["query"] ?? entities["product"] ?? "provider request",
            language: .uk,
            intent: intent,
            entities: entities
        )
    }
}
