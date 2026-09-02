import Foundation
import Testing
@testable import UniversalAssistant

private func segment(_ now: Date, offset: TimeInterval = 0) -> TicketSegment {
    .init(origin: "Kyiv", destination: "Lviv", departure: now.addingTimeInterval(3_600 + offset),
          arrival: now.addingTimeInterval(10_800 + offset))
}

private func ticket(_ id: String, now: Date, fare: Decimal? = 500,
                    inventory: TicketInventoryEvidence = .unknown,
                    segments: [TicketSegment]? = nil) -> TicketOffer {
    .init(id: id, providerID: "provider", mode: .rail, segments: segments ?? [segment(now)],
          fare: fare.map { .init(amount: $0, currency: "UAH") }, inventory: inventory,
          fareObservedAt: fare == nil ? nil : now,
          exactPurchaseURL: URL(string: "https://tickets.example/offers/\(id)")!)
}

private actor TicketHTTPRecorder: TicketHTTPTransport {
    var responses: [(Data, Int)]
    private(set) var requests: [URLRequest] = []
    init(_ responses: [(Data, Int)]) { self.responses = responses }
    func data(for request: URLRequest) throws -> (Data, Int) {
        requests.append(request)
        return responses.removeFirst()
    }
    func recorded() -> [URLRequest] { requests }
}

@Suite("Truthful ticket engine") struct TicketEngineTests {
    @Test func unknownInventoryCannotSatisfyVerifiedSeatRequest() {
        let now = Date()
        #expect(throws: TicketEngineError.noVerifiedOffers) {
            try TicketEngine().rank([ticket("unknown", now: now)],
                                    request: .init(requiresVerifiedInventory: true), now: now)
        }
    }

    @Test func staleInventoryCannotBecomePurchasable() {
        let now = Date()
        let offer = ticket("stale", now: now,
                           inventory: .verifiedAvailable(source: "provider-api", observedAt: now.addingTimeInterval(-1_000)))
        #expect(throws: TicketEngineError.invalidExactDestination) {
            try TicketEngine().purchaseHandoff(for: offer, now: now)
        }
    }

    @Test func hardBudgetRejectsMissingOrStaleFareEvidence() throws {
        let now = Date()
        let result = try TicketEngine().rank([
            ticket("missing", now: now, fare: nil),
            ticket("valid", now: now, fare: 400)
        ], request: .init(maximumPrice: .init(amount: 450, currency: "UAH")), now: now)
        #expect(result.map(\.id) == ["valid"])
    }

    @Test func invalidConnectingItineraryIsRejected() {
        let now = Date()
        let first = segment(now), overlapping = segment(now, offset: 1_000)
        #expect(throws: TicketEngineError.noVerifiedOffers) {
            try TicketEngine().rank([ticket("overlap", now: now, segments: [first, overlapping])],
                                    request: .init(), now: now)
        }
    }

    @Test func exactFreshHandoffPreparesDestinationButNeverClaimsPurchase() throws {
        let now = Date()
        let offer = ticket("live", now: now,
                           inventory: .verifiedAvailable(source: "provider-api", observedAt: now))
        let handoff = try TicketEngine().purchaseHandoff(for: offer, now: now)
        #expect(handoff.state == .destinationPrepared)
        #expect(handoff.destination.path == "/offers/live")
    }

    @Test func originDestinationDurationAndProviderAreHardParameters() throws {
        let now = Date()
        let request = TicketSearchRequest(allowedModes: [.rail], departureNotBefore: now,
            arrivalNotAfter: now.addingTimeInterval(20_000), maximumPrice: nil, maximumTransfers: 0,
            requiresVerifiedInventory: false, origin: "Kyiv", destination: "Lviv",
            maximumDurationSeconds: 8_000, providerIDs: ["provider"])
        #expect(try TicketEngine().rank([ticket("valid", now: now)], request: request, now: now).map(\.id) == ["valid"])
        var rejected = request
        rejected.destination = "Odesa"
        #expect(throws: TicketEngineError.noVerifiedOffers) {
            try TicketEngine().rank([ticket("wrong", now: now)], request: rejected, now: now)
        }
    }

    @Test func officialHTTPProviderInjectsCredentialParsesAndRejectsCrossProviderRows() async throws {
        let now = Date()
        let valid = ticket("valid", now: now,
            inventory: .verifiedAvailable(source: "official:inventory", observedAt: now))
        var foreign = valid
        foreign = .init(id: "foreign", providerID: "other", mode: foreign.mode, segments: foreign.segments,
            fare: foreign.fare, inventory: foreign.inventory, fareObservedAt: foreign.fareObservedAt,
            exactPurchaseURL: foreign.exactPurchaseURL)
        let transport = TicketHTTPRecorder([(try JSONEncoder().encode([valid, foreign]), 200)])
        let provider = try OfficialTicketHTTPProvider(providerID: "provider",
            searchURL: URL(string: "https://tickets.example/search")!, bearerToken: "secret", transport: transport)
        let result = try await provider.search(.init(origin: "Kyiv", destination: "Lviv"))
        #expect(result.map(\.id) == ["valid"])
        let recorded = await transport.recorded()
        #expect(recorded.first?.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(recorded.first?.timeoutInterval == 8)
    }

    @Test func officialHTTPProviderFailsClosedOnCredentialAndRateLimit() async throws {
        let endpoint = URL(string: "https://tickets.example/search")!
        #expect(throws: TicketHTTPError.missingCredential) {
            try OfficialTicketHTTPProvider(providerID: "provider", searchURL: endpoint, bearerToken: " ")
        }
        let provider = try OfficialTicketHTTPProvider(providerID: "provider", searchURL: endpoint,
            bearerToken: "token", transport: TicketHTTPRecorder([(Data("{}".utf8), 429)]))
        await #expect(throws: TicketHTTPError.rateLimited) { try await provider.search(.init()) }
    }
}
