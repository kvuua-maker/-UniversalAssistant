import Foundation
import Testing
@testable import UniversalAssistantServer

@Suite("Partner runtime policy and cost quota")
struct PartnerRuntimePolicyTests {
    private func storeURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("partner-policy-\(UUID().uuidString).json")
    }

    @Test func featureFlagsAreVersionedScopedAndFailClosed() async throws {
        let store = try PartnerRuntimePolicyStore(fileURL: storeURL()), now = Date()
        let snapshot = PartnerRuntimePolicySnapshot(version: 1, effectiveFrom: now.addingTimeInterval(-1),
            expiresAt: now.addingTimeInterval(100), rules: [
                .init(feature: .sponsoredPlacements, enabled: true, countryCodes: ["UA"], categories: ["hotel"])
            ], sourceReference: "remote-config-v1")
        try await store.install(snapshot, actor: "release-admin", reasonCode: "approved_rollout", at: now)
        #expect(await store.isEnabled(.sponsoredPlacements, countryCode: "UA", category: "hotel", now: now))
        #expect(!(await store.isEnabled(.sponsoredPlacements, countryCode: "DE", category: "hotel", now: now)))
        #expect(!(await store.isEnabled(.partnerWebhooks, countryCode: "UA", category: "hotel", now: now)))
        #expect(!(await store.isEnabled(.sponsoredPlacements, countryCode: "UA", category: "hotel",
                                       now: now.addingTimeInterval(101))))
        await #expect(throws: PartnerRuntimePolicyError.staleVersion) {
            try await store.install(snapshot, actor: "release-admin", reasonCode: "duplicate", at: now)
        }
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

    @Test func knownConfigurationCanRollbackWithoutRewritingHistory() async throws {
        let url = storeURL(), store = try PartnerRuntimePolicyStore(fileURL: url), now = Date()
        let v1 = PartnerRuntimePolicySnapshot(
            version: 1, effectiveFrom: now.addingTimeInterval(-10),
            expiresAt: now.addingTimeInterval(100), rules: [
                .init(feature: .partnerFeeds, enabled: false, countryCodes: [], categories: [])
            ], sourceReference: "reviewed-v1"
        )
        let v2 = PartnerRuntimePolicySnapshot(
            version: 2, effectiveFrom: now.addingTimeInterval(-5),
            expiresAt: now.addingTimeInterval(100), rules: [
                .init(feature: .partnerFeeds, enabled: true, countryCodes: [], categories: [])
            ], sourceReference: "reviewed-v2"
        )
        try await store.install(v1, actor: "config-admin", reasonCode: "initial", at: now)
        try await store.install(v2, actor: "config-admin", reasonCode: "feed_rollout", at: now)
        #expect(await store.isEnabled(.partnerFeeds, countryCode: "UA", category: "grocery", now: now))
        #expect(try await store.rollback(to: 1, actor: "incident-commander",
                                        reasonCode: "provider_degradation", at: now).sourceReference == "reviewed-v1")
        #expect(!(await store.isEnabled(.partnerFeeds, countryCode: "UA", category: "grocery", now: now)))
        await #expect(throws: PartnerRuntimePolicyError.unknownVersion) {
            try await store.rollback(to: 99, actor: "admin", reasonCode: "test", at: now)
        }
        let events = await store.auditTrail()
        #expect(events.map(\.sequence) == Array(1...events.count))
        #expect(events.contains { $0.area == .provider && $0.reasonCode == "feed_rollout" })
        #expect(events.last?.fromVersion == 2 && events.last?.toVersion == 1)

        let restored = try PartnerRuntimePolicyStore(fileURL: url)
        #expect(await restored.snapshot()?.version == 1)
        #expect(await restored.auditTrail() == events)
    }

    @Test func sponsoredAndFeatureChangesRequireActorReasonAndAreAudited() async throws {
        let store = try PartnerRuntimePolicyStore(fileURL: storeURL()), now = Date()
        let snapshot = PartnerRuntimePolicySnapshot(
            version: 1, effectiveFrom: now.addingTimeInterval(-1), expiresAt: now.addingTimeInterval(100),
            rules: [.init(feature: .sponsoredPlacements, enabled: true,
                          countryCodes: ["UA"], categories: ["hotel"])], sourceReference: "signed-config-1")
        await #expect(throws: PartnerRuntimePolicyError.invalidAuditContext) {
            try await store.install(snapshot, actor: "", reasonCode: "rollout", at: now)
        }
        try await store.install(snapshot, actor: "commercial-admin", reasonCode: "approved_campaign", at: now)
        let areas = Set(await store.auditTrail().map(\.area))
        #expect(areas == [.remoteConfig, .featureFlag, .sponsoredRanking])
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
    @Test func costQuotaManagerTracksOperationalSignals() async {
        let now = Date()
        let policy = PartnerQuotaPolicy(policyID: "weather", version: 1, scopeID: "weather", periodStart: now.addingTimeInterval(-1), periodEnd: now.addingTimeInterval(100), maximumCalls: 2, maximumCost: .init(amount: Decimal(string: "0.20")!, currencyCode: "USD"))
        let manager = CostQuotaManager(policiesByProvider: ["weather": policy])
        let cost = LedgerMoney(amount: Decimal(string: "0.10")!, currencyCode: "USD")
        #expect(await manager.reserve(providerID: "weather", operationID: "cached", estimatedCost: cost, cacheHit: true, at: now) == .allowed)
        #expect(await manager.reserve(providerID: "weather", operationID: "cached", estimatedCost: cost, cacheHit: true, at: now) == .allowed)
        #expect(await manager.reserve(providerID: "weather", operationID: "network", estimatedCost: cost, at: now) == .allowed)
        await manager.recordOutcome(providerID: "weather", operationID: "network", outcome: .rateLimited)
        await manager.recordOutcome(providerID: "weather", operationID: "network", outcome: .rateLimited)
        let usage = await manager.snapshot(providerID: "weather")
        #expect(usage?.requestCount == 2)
        #expect(usage?.allowedCount == 2)
        #expect(usage?.cacheHitCount == 1)
        #expect(usage?.rateLimitedCount == 1)
        #expect(usage?.failureCount == 1)
        #expect(usage?.estimatedCost.amount == Decimal(string: "0.10")!)
        #expect(usage?.failureRate == Decimal(string: "0.5")!)
        #expect(usage?.cacheEffectiveness == Decimal(string: "0.5")!)
    }

    @Test func remoteConfigControlsProvidersAndFeatureTargeting() async throws {
        let now = Date(), store = try PartnerRuntimePolicyStore(fileURL: storeURL())
        let snapshot = PartnerRuntimePolicySnapshot(version: 1, effectiveFrom: now.addingTimeInterval(-1), expiresAt: now.addingTimeInterval(100), rules: [
            .init(feature: .partnerFeeds, enabled: true, countryCodes: ["UA"], categories: ["grocery"], languageCodes: ["uk"], minimumAppVersion: "2.1.0")
        ], sourceReference: "signed-config", providerRules: [
            .init(providerID: "priority", enabled: true, priority: 1, timeoutMilliseconds: 800, countryCodes: ["UA"], emergencyDisabled: false),
            .init(providerID: "later", enabled: true, priority: 5, timeoutMilliseconds: 2_000, countryCodes: [], emergencyDisabled: false),
            .init(providerID: "killed", enabled: true, priority: 0, timeoutMilliseconds: 500, countryCodes: ["UA"], emergencyDisabled: true)
        ])
        try await store.install(snapshot, actor: "admin", reasonCode: "rollout", at: now)
        #expect(await store.providers(countryCode: "UA", now: now).map(\.providerID) == ["priority", "later"])
        #expect(await store.providers(countryCode: "DE", now: now).map(\.providerID) == ["later"])
        #expect(await store.isEnabled(.partnerFeeds, countryCode: "UA", category: "grocery", languageCode: "uk", appVersion: "2.1.1", now: now))
        #expect(!(await store.isEnabled(.partnerFeeds, countryCode: "UA", category: "grocery", languageCode: "en", appVersion: "2.1.1", now: now)))
        #expect(!(await store.isEnabled(.partnerFeeds, countryCode: "UA", category: "grocery", languageCode: "uk", appVersion: "2.0.9", now: now)))
    }

    @Test func unsafeRemoteTimeoutFailsClosed() async throws {
        let now = Date(), store = try PartnerRuntimePolicyStore(fileURL: storeURL())
        let invalid = PartnerRuntimePolicySnapshot(version: 1, effectiveFrom: now.addingTimeInterval(-1), expiresAt: now.addingTimeInterval(100), rules: [], sourceReference: "bad", providerRules: [
            .init(providerID: "provider", enabled: true, priority: 1, timeoutMilliseconds: 99, countryCodes: [], emergencyDisabled: false)
        ])
        await #expect(throws: PartnerRuntimePolicyError.invalidSnapshot) {
            try await store.install(invalid, actor: "admin", reasonCode: "invalid", at: now)
        }
    }
}
