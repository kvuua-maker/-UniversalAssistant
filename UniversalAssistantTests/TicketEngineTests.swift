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
}
