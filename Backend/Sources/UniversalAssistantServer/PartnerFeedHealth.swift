import Foundation

enum PartnerDataFreshness: String, Codable, Sendable {
    case verifiedLive = "VERIFIED_LIVE"
    case partnerProvidedRecent = "PARTNER_PROVIDED_RECENT"
    case stale = "STALE"
    case unknown = "UNKNOWN"
}
enum PartnerFeedSource: String, Codable, Sendable { case liveAPI, partnerFeed, manualProfile }
enum PartnerHealthState: String, Codable, Sendable {
    case activeHealthy = "ACTIVE_HEALTHY"
    case degraded = "DEGRADED"
    case staleData = "STALE_DATA"
    case temporarilyUnavailable = "TEMPORARILY_UNAVAILABLE"
    case suspended = "SUSPENDED"
}

struct PartnerFeedRecord: Equatable, Codable, Sendable {
    let partnerID: UUID
    let recordID: String
    let category: String
    let source: PartnerFeedSource
    let sourceTimestamp: Date?
    let receivedAt: Date
    let payloadReference: String
}

struct PartnerFeedPolicy: Equatable, Sendable {
    let liveMaximumAge: TimeInterval
    let recentMaximumAge: TimeInterval
    let failureThreshold: Int
}

struct PartnerFeedHealthEvaluator: Sendable {
    func freshness(_ record: PartnerFeedRecord, policy: PartnerFeedPolicy, now: Date = .now) -> PartnerDataFreshness {
        guard let timestamp = record.sourceTimestamp else { return .unknown }
        let age = now.timeIntervalSince(timestamp)
        guard age >= -60 else { return .unknown }
        if record.source == .liveAPI && age <= policy.liveMaximumAge { return .verifiedLive }
        if age <= policy.recentMaximumAge { return .partnerProvidedRecent }
        return .stale
    }

    func health(onboarding: PartnerOnboardingState, freshness: PartnerDataFreshness,
                consecutiveFailures: Int, policy: PartnerFeedPolicy) -> PartnerHealthState {
        guard onboarding == .active else { return .suspended }
        if consecutiveFailures >= policy.failureThreshold { return .temporarilyUnavailable }
        if freshness == .stale || freshness == .unknown { return .staleData }
        if consecutiveFailures > 0 { return .degraded }
        return .activeHealthy
    }
}

enum PartnerFeedDirectoryError: Error, Equatable, Sendable { case invalidLimit }
actor PartnerFeedDirectory {
    private var recordsByCategory: [String: [PartnerFeedRecord]] = [:]

    func upsert(_ record: PartnerFeedRecord) {
        var records = recordsByCategory[record.category, default: []]
        records.removeAll { $0.partnerID == record.partnerID && $0.recordID == record.recordID }
        records.append(record); recordsByCategory[record.category] = records
    }

    func query(category: String, offset: Int = 0, limit: Int = 50) throws -> [PartnerFeedRecord] {
        guard offset >= 0, (1...100).contains(limit) else { throw PartnerFeedDirectoryError.invalidLimit }
        let records = recordsByCategory[category, default: []].sorted { $0.recordID < $1.recordID }
        guard offset < records.count else { return [] }
        return Array(records.dropFirst(offset).prefix(limit))
    }
}

struct MonetizableHandoffGate: Sendable {
    func allows(onboarding: PartnerOnboardingState, health: PartnerHealthState,
                freshness: PartnerDataFreshness) -> Bool {
        onboarding == .active && [.activeHealthy, .degraded].contains(health) &&
        [.verifiedLive, .partnerProvidedRecent].contains(freshness)
    }
}

actor PartnerOffboardingService {
    private let credentials: PartnerWebhookCredentialVault
    init(credentials: PartnerWebhookCredentialVault) { self.credentials = credentials }
    func revokeIntegrationCredentials(partnerID: UUID) async { await credentials.revokeAll(partnerID: partnerID) }
}
