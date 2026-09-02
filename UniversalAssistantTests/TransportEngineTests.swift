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
        #expect(option.mode == .taxi)
        #expect(option.evidence.kind == .realTime)
        #expect(option.departure == now.addingTimeInterval(120))
        #expect(TransportEngine().option(from: ride, source: "  ") == nil)
    }

    @Test func supportsEveryCanonicalModeAndTruthfulPublicTransportDetails() throws {
        let now = Date()
        #expect(Set(TransportMode.allCases) == [.walking, .driving, .publicTransit, .train, .intercityBus, .air, .taxi, .multimodal])
        var option = transport("metro", observedAt: now, departure: now.addingTimeInterval(60),
                               arrival: now.addingTimeInterval(900), duration: 840, price: 8,
                               transfers: 1, availability: .unknown)
        option.segments = [
            .init(kind: .walking, durationSeconds: 180),
            .init(kind: .transit, routeName: "M2", originStop: "Maidan", destinationStop: "Pochaina",
                  departure: now.addingTimeInterval(240), arrival: now.addingTimeInterval(780), durationSeconds: 540)
        ]
        let result = try TransportEngine().rank([option], request: .init(), now: now)
        #expect(result.first?.segments.last?.routeName == "M2")
        #expect(result.first?.price == Money(amount: 8, currency: "UAH"))
    }

    @Test func malformedTransitSegmentCannotBecomeAResult() {
        let now = Date()
        var option = transport("bad", observedAt: now, duration: 600)
        option.segments = [.init(kind: .transit, routeName: nil, originStop: "A", destinationStop: "B")]
        #expect(throws: TransportEngineError.noVerifiedOptions) {
            try TransportEngine().rank([option], request: .init(), now: now)
        }
    }
}
