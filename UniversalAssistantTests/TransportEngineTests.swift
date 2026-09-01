import Foundation
import Testing
@testable import UniversalAssistant

private func transport(
    _ id: String, mode: TransportMode = .publicTransit,
    kind: TransportEvidenceKind = .scheduled,
    observedAt: Date, departure: Date? = nil, arrival: Date? = nil,
    duration: TimeInterval? = nil, price: Decimal? = nil,
    transfers: Int? = nil, availability: VerifiedServiceAvailability = .unknown
) -> TransportOption {
    .init(id: id, providerID: "provider-\(id)", mode: mode, departure: departure, arrival: arrival,
          durationSeconds: duration, price: price.map { .init(amount: $0, currency: "UAH") },
          transfers: transfers, availability: availability,
          evidence: .init(source: "official-\(id)", kind: kind, observedAt: observedAt))
}

@Suite("Truthful unified transport engine") struct TransportEngineTests {
    @Test func scheduleNeverBecomesLiveAvailabilityEvidence() {
        let now = Date()
        #expect(throws: TransportEngineError.noVerifiedOptions) {
            try TransportEngine().rank([
                transport("schedule", observedAt: now, duration: 900, availability: .available)
            ], request: .init(requiresVerifiedAvailability: true), now: now)
        }
    }

    @Test func realTimeFreshAvailabilityCanSatisfyStrictRequest() throws {
        let now = Date()
        let options = try TransportEngine().rank([
            transport("stale", kind: .realTime, observedAt: now.addingTimeInterval(-600), duration: 600, availability: .available),
            transport("live", kind: .realTime, observedAt: now, duration: 900, availability: .available)
        ], request: .init(requiresVerifiedAvailability: true), now: now)
        #expect(options.map(\.id) == ["live"])
    }

    @Test func hardTimePriceAndTransferConstraintsRejectMissingEvidence() throws {
        let now = Date(), departure = now.addingTimeInterval(600), arrival = now.addingTimeInterval(1_800)
        let request = TransportRequest(departureNotBefore: now, arrivalNotAfter: now.addingTimeInterval(2_000),
                                       maximumDurationSeconds: 1_500,
                                       maximumPrice: .init(amount: 50, currency: "UAH"), maximumTransfers: 1)
        let result = try TransportEngine().rank([
            transport("missing-price", observedAt: now, departure: departure, arrival: arrival, duration: 1_200, transfers: 0),
            transport("valid", observedAt: now, departure: departure, arrival: arrival, duration: 1_200, price: 40, transfers: 1)
        ], request: request, now: now)
        #expect(result.map(\.id) == ["valid"])
    }

    @Test func stableRankingPrefersKnownEarlierArrival() throws {
        let now = Date()
        let result = try TransportEngine().rank([
            transport("unknown", observedAt: now, duration: 500),
            transport("later", observedAt: now, arrival: now.addingTimeInterval(2_000), duration: 1_000),
            transport("earlier", observedAt: now, arrival: now.addingTimeInterval(1_000), duration: 900)
        ], request: .init(), now: now)
        #expect(result.map(\.id) == ["earlier", "later", "unknown"])
    }

    @Test func rideAdapterPreservesOnlyExplicitProviderEvidence() throws {
        let now = Date()
        let ride = RideOffer(id: "ride", providerID: "uber", price: .init(amount: 200, currency: "UAH"),
                             pickupWaitSeconds: 120, estimatedArrival: now.addingTimeInterval(900),
                             availability: .available, evidenceTimestamp: now,
                             exactHandoffURL: URL(string: "https://m.uber.com/looking")!)
        let option = try #require(TransportEngine().option(from: ride, source: "provider-api"))
        #expect(option.mode == .ride)
        #expect(option.evidence.kind == .realTime)
        #expect(option.departure == now.addingTimeInterval(120))
        #expect(TransportEngine().option(from: ride, source: "  ") == nil)
    }
}
