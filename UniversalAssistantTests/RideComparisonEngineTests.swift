import Foundation
import Testing
@testable import UniversalAssistant

private func ride(_ id: String, price: Decimal? = nil, currency: String = "UAH", wait: TimeInterval? = nil,
                  availability: VerifiedServiceAvailability = .available, capabilities: RideCapabilities = [],
                  timestamp: Date? = .now) -> RideOffer {
    .init(id: id, providerID: "provider-\(id)", price: price.map { .init(amount: $0, currency: currency) },
          pickupWaitSeconds: wait, availability: availability, capabilities: capabilities,
          evidenceTimestamp: timestamp, exactHandoffURL: URL(string: "https://rides.example/trips/\(id)")!)
}

@Suite("Truthful ride comparison") struct RideComparisonEngineTests {
    @Test func cheapestUsesOnlyFreshAvailableComparableQuotes() throws {
        let now = Date()
        let result = try RideComparisonEngine().compare([
            ride("stale", price: 100, wait: 60, timestamp: now.addingTimeInterval(-600)),
            ride("unavailable", price: 90, wait: 60, availability: .unavailable, timestamp: now),
            ride("b", price: 200, wait: 120, timestamp: now), ride("a", price: 150, wait: 300, timestamp: now)
        ], request: .init(mode: .cheapest), now: now)
        #expect(result.map(\.id) == ["a", "b"])
    }

    @Test func budgetAndMaximumWaitAreHardEvidenceConstraints() throws {
        let result = try RideComparisonEngine().compare([
            ride("unknown-wait", price: 100), ride("slow", price: 100, wait: 600),
            ride("expensive", price: 400, wait: 60), ride("valid", price: 250, wait: 240)
        ], request: .init(mode: .optimal, maximumPrice: .init(amount: 300, currency: "UAH"), maximumWaitSeconds: 300))
        #expect(result.map(\.id) == ["valid"])
    }

    @Test func requiredCapabilityCannotBeInferredFromClassOrProvider() throws {
        let child: RideCapabilities = [.childSeat]
        let result = try RideComparisonEngine().compare([
            ride("plain", price: 100, wait: 60),
            ride("verified-child", price: 150, wait: 90, capabilities: child)
        ], request: .init(mode: .childSeat, requiredCapabilities: child))
        #expect(result.map(\.id) == ["verified-child"])
    }

    @Test func cheapestRejectsMixedCurrenciesWithoutVerifiedFX() {
        #expect(throws: RideComparisonError.incomparableCurrencies) {
            try RideComparisonEngine().compare([
                ride("uah", price: 200, wait: 60), ride("eur", price: 5, currency: "EUR", wait: 60)
            ], request: .init(mode: .cheapest))
        }
    }

    @Test func missingEvidenceNeverBecomesLivePriceEtaOrAvailability() {
        #expect(throws: RideComparisonError.noVerifiedOffers) {
            try RideComparisonEngine().compare([ride("unknown", price: 1, wait: 1, timestamp: nil)],
                                               request: .init(mode: .optimal))
        }
    }
}
