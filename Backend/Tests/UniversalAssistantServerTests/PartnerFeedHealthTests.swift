import Foundation
import Testing
@testable import UniversalAssistantServer

@Suite("Partner feed health and offboarding")
struct PartnerFeedHealthTests {
    private let policy = PartnerFeedPolicy(liveMaximumAge: 300, recentMaximumAge: 3600, failureThreshold: 3)

    @Test func freshnessNeverPresentsStaleOrManualDataAsVerifiedLive() {
        let now = Date(), evaluator = PartnerFeedHealthEvaluator(), partner = UUID()
        let live = PartnerFeedRecord(partnerID: partner, recordID: "live", category: "food", source: .liveAPI,
            sourceTimestamp: now.addingTimeInterval(-10), receivedAt: now, payloadReference: "live-1")
        let manual = PartnerFeedRecord(partnerID: partner, recordID: "manual", category: "food", source: .manualProfile,
            sourceTimestamp: now.addingTimeInterval(-10), receivedAt: now, payloadReference: "manual-1")
        let stale = PartnerFeedRecord(partnerID: partner, recordID: "stale", category: "food", source: .partnerFeed,
            sourceTimestamp: now.addingTimeInterval(-7200), receivedAt: now, payloadReference: "feed-1")
        #expect(evaluator.freshness(live, policy: policy, now: now) == .verifiedLive)
        #expect(evaluator.freshness(manual, policy: policy, now: now) == .partnerProvidedRecent)
        #expect(evaluator.freshness(stale, policy: policy, now: now) == .stale)
    }

    @Test func failingPartnerIsIsolatedAndQueriesAreBoundedPaginated() async throws {
        let evaluator = PartnerFeedHealthEvaluator()
        #expect(evaluator.health(onboarding: .active, freshness: .verifiedLive,
                                 consecutiveFailures: 3, policy: policy) == .temporarilyUnavailable)
        #expect(evaluator.health(onboarding: .active, freshness: .verifiedLive,
                                 consecutiveFailures: 0, policy: policy) == .activeHealthy)
        let directory = PartnerFeedDirectory(), now = Date(), partner = UUID()
        for index in 0..<3 {
            await directory.upsert(.init(partnerID: partner, recordID: "\(index)", category: "hotel",
                source: .partnerFeed, sourceTimestamp: now, receivedAt: now, payloadReference: "ref-\(index)"))
        }
        #expect(try await directory.query(category: "hotel", offset: 1, limit: 1).map(\.recordID) == ["1"])
        await #expect(throws: PartnerFeedDirectoryError.invalidLimit) {
            try await directory.query(category: "hotel", limit: 101)
        }
    }

    @Test func suspendedPartnerGetsNoNewHandoffAndCredentialsAreRevoked() async throws {
        let gate = MonetizableHandoffGate()
        #expect(gate.allows(onboarding: .active, health: .activeHealthy, freshness: .verifiedLive))
        #expect(!gate.allows(onboarding: .suspended, health: .suspended, freshness: .verifiedLive))
        #expect(!gate.allows(onboarding: .terminated, health: .suspended, freshness: .partnerProvidedRecent))

        let vault = PartnerWebhookCredentialVault(), partner = UUID()
        try await vault.install(partnerID: partner, keyID: "key", secret: Data(repeating: 1, count: 32))
        await PartnerOffboardingService(credentials: vault).revokeIntegrationCredentials(partnerID: partner)
        await #expect(throws: PartnerWebhookError.credentialUnavailable) {
            try await vault.secret(partnerID: partner, keyID: "key")
        }
    }
}
