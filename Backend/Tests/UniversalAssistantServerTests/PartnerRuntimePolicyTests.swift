import Foundation
import Testing
@testable import UniversalAssistantServer

@Suite("Partner runtime policy and cost quota")
struct PartnerRuntimePolicyTests {
    @Test func featureFlagsAreVersionedScopedAndFailClosed() async throws {
        let store = PartnerRuntimePolicyStore(), now = Date()
        let snapshot = PartnerRuntimePolicySnapshot(version: 1, effectiveFrom: now.addingTimeInterval(-1),
            expiresAt: now.addingTimeInterval(100), rules: [
                .init(feature: .sponsoredPlacements, enabled: true, countryCodes: ["UA"], categories: ["hotel"])
            ], sourceReference: "remote-config-v1")
        try await store.install(snapshot)
        #expect(await store.isEnabled(.sponsoredPlacements, countryCode: "UA", category: "hotel", now: now))
        #expect(!(await store.isEnabled(.sponsoredPlacements, countryCode: "DE", category: "hotel", now: now)))
        #expect(!(await store.isEnabled(.partnerWebhooks, countryCode: "UA", category: "hotel", now: now)))
        #expect(!(await store.isEnabled(.sponsoredPlacements, countryCode: "UA", category: "hotel",
                                       now: now.addingTimeInterval(101))))
        await #expect(throws: PartnerRuntimePolicyError.staleVersion) { try await store.install(snapshot) }
    }

    @Test func quotaReservationIsAtomicExactAndIdempotent() async {
        let now = Date()
        let ledger = PartnerCostQuotaLedger(policy: .init(policyID: "quota", version: 1, scopeID: "partner:provider",
            periodStart: now.addingTimeInterval(-1), periodEnd: now.addingTimeInterval(100), maximumCalls: 2,
            maximumCost: .init(amount: Decimal(string: "0.30")!, currencyCode: "USD")))
        let cost = LedgerMoney(amount: Decimal(string: "0.10")!, currencyCode: "USD")
        #expect(await ledger.reserve(operationID: "one", estimatedCost: cost, at: now) == .allowed)
        #expect(await ledger.reserve(operationID: "one", estimatedCost: cost, at: now) == .allowed)
        #expect(await ledger.reserve(operationID: "two", estimatedCost: cost, at: now) == .allowed)
        #expect(await ledger.reserve(operationID: "three", estimatedCost: cost, at: now) == .denied(.callLimit))
        let usage = await ledger.usage()
        #expect(usage.calls == 2); #expect(usage.cost == Decimal(string: "0.20")!)
        #expect(await ledger.auditTrail().count == 3)
    }

    @Test func costAndCurrencyLimitsFailClosedWithoutConsumption() async {
        let now = Date()
        let ledger = PartnerCostQuotaLedger(policy: .init(policyID: "quota", version: 1, scopeID: "provider",
            periodStart: now.addingTimeInterval(-1), periodEnd: now.addingTimeInterval(100), maximumCalls: 5,
            maximumCost: .init(amount: 1, currencyCode: "USD")))
        #expect(await ledger.reserve(operationID: "expensive", estimatedCost: .init(amount: 2, currencyCode: "USD"), at: now) == .denied(.costLimit))
        #expect(await ledger.reserve(operationID: "wrong-currency", estimatedCost: .init(amount: 1, currencyCode: "EUR"), at: now) == .denied(.invalidPolicy))
        #expect(await ledger.usage().calls == 0)
    }
}
