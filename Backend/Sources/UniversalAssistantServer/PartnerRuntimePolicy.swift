import Foundation

enum PartnerFeature: String, Codable, CaseIterable, Sendable {
    case partnerApplications
    case monetizableHandoffs
    case sponsoredPlacements
    case partnerFeeds
    case partnerWebhooks
}

struct PartnerFeatureRule: Equatable, Codable, Sendable {
    let feature: PartnerFeature
    let enabled: Bool
    let countryCodes: Set<String>
    let categories: Set<String>
}

struct PartnerRuntimePolicySnapshot: Equatable, Codable, Sendable {
    let version: Int
    let effectiveFrom: Date
    let expiresAt: Date
    let rules: [PartnerFeatureRule]
    let sourceReference: String
}

enum PartnerRuntimePolicyError: Error, Equatable, Sendable {
    case invalidSnapshot
    case staleVersion
    case unknownVersion
    case invalidAuditContext
}

enum AdministrativeConfigurationArea: String, Codable, Sendable {
    case remoteConfig, featureFlag, sponsoredRanking, provider, businessVerification
}

struct AdministrativeConfigurationAuditEvent: Equatable, Codable, Sendable {
    let sequence: Int
    let area: AdministrativeConfigurationArea
    let actorReference: String
    let reasonCode: String
    let fromVersion: Int?
    let toVersion: Int
    let sourceReference: String
    let occurredAt: Date
}

actor PartnerRuntimePolicyStore {
    private struct PersistedState: Codable {
        var currentVersion: Int?
        var versions: [Int: PartnerRuntimePolicySnapshot]
        var audit: [AdministrativeConfigurationAuditEvent]
    }

    private let fileURL: URL
    private var current: PartnerRuntimePolicySnapshot?
    private var versions: [Int: PartnerRuntimePolicySnapshot] = [:]
    private var audit: [AdministrativeConfigurationAuditEvent] = []

    init(fileURL: URL) throws {
        self.fileURL = fileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let state = try JSONDecoder().decode(PersistedState.self, from: Data(contentsOf: fileURL))
            versions = state.versions
            audit = state.audit
            current = state.currentVersion.flatMap { state.versions[$0] }
        }
    }

    func install(_ snapshot: PartnerRuntimePolicySnapshot, actor: String,
                 reasonCode: String, at: Date = .now) throws {
        guard snapshot.version > 0, snapshot.effectiveFrom < snapshot.expiresAt,
              !snapshot.sourceReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Set(snapshot.rules.map(\.feature)).count == snapshot.rules.count else {
            throw PartnerRuntimePolicyError.invalidSnapshot
        }
        guard Self.validAuditValue(actor), Self.validAuditValue(reasonCode) else {
            throw PartnerRuntimePolicyError.invalidAuditContext
        }
        guard current.map({ snapshot.version > $0.version }) ?? true else {
            throw PartnerRuntimePolicyError.staleVersion
        }
        let previous = current?.version
        versions[snapshot.version] = snapshot
        current = snapshot
        let areas = Self.areas(for: snapshot)
        for area in areas {
            audit.append(.init(sequence: audit.count + 1, area: area,
                               actorReference: actor, reasonCode: reasonCode,
                               fromVersion: previous, toVersion: snapshot.version,
                               sourceReference: snapshot.sourceReference, occurredAt: at))
        }
        try persist()
    }

    func isEnabled(_ feature: PartnerFeature, countryCode: String, category: String,
                   now: Date = .now) -> Bool {
        guard let current, current.effectiveFrom <= now, now < current.expiresAt,
              let rule = current.rules.first(where: { $0.feature == feature }), rule.enabled else { return false }
        let countryAllowed = rule.countryCodes.isEmpty || rule.countryCodes.contains(countryCode.uppercased())
        let categoryAllowed = rule.categories.isEmpty || rule.categories.contains(category.lowercased())
        return countryAllowed && categoryAllowed
    }

    func snapshot() -> PartnerRuntimePolicySnapshot? { current }
    func auditTrail() -> [AdministrativeConfigurationAuditEvent] { audit }

    @discardableResult
    func rollback(to version: Int, actor: String, reasonCode: String,
                  at: Date = .now) throws -> PartnerRuntimePolicySnapshot {
        guard let snapshot = versions[version] else {
            throw PartnerRuntimePolicyError.unknownVersion
        }
        guard Self.validAuditValue(actor), Self.validAuditValue(reasonCode) else {
            throw PartnerRuntimePolicyError.invalidAuditContext
        }
        let previous = current?.version
        current = snapshot
        audit.append(.init(sequence: audit.count + 1, area: .remoteConfig,
                           actorReference: actor, reasonCode: reasonCode,
                           fromVersion: previous, toVersion: version,
                           sourceReference: snapshot.sourceReference, occurredAt: at))
        try persist()
        return snapshot
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let state = PersistedState(currentVersion: current?.version, versions: versions, audit: audit)
        try JSONEncoder().encode(state).write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    private static func areas(for snapshot: PartnerRuntimePolicySnapshot) -> [AdministrativeConfigurationArea] {
        var areas: Set<AdministrativeConfigurationArea> = [.remoteConfig, .featureFlag]
        if snapshot.rules.contains(where: { $0.feature == .sponsoredPlacements }) { areas.insert(.sponsoredRanking) }
        if snapshot.rules.contains(where: { $0.feature == .partnerFeeds || $0.feature == .partnerWebhooks }) {
            areas.insert(.provider)
        }
        return areas.sorted { $0.rawValue < $1.rawValue }
    }

    private static func validAuditValue(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 128
    }
}

struct PartnerQuotaPolicy: Equatable, Codable, Sendable {
    let policyID: String
    let version: Int
    let scopeID: String
    let periodStart: Date
    let periodEnd: Date
    let maximumCalls: Int
    let maximumCost: LedgerMoney
}

enum PartnerQuotaDenial: String, Codable, Sendable { case callLimit, costLimit, invalidPolicy }
enum PartnerQuotaDecision: Equatable, Sendable { case allowed, denied(PartnerQuotaDenial) }

struct PartnerQuotaAuditEvent: Equatable, Sendable {
    let sequence: Int
    let operationID: String
    let scopeID: String
    let decision: PartnerQuotaDecision
    let requestedCost: LedgerMoney
    let occurredAt: Date
}

actor PartnerCostQuotaLedger {
    private let policy: PartnerQuotaPolicy
    private var calls = 0
    private var cost = Decimal.zero
    private var operationDecisions: [String: PartnerQuotaDecision] = [:]
    private var audit: [PartnerQuotaAuditEvent] = []

    init(policy: PartnerQuotaPolicy) { self.policy = policy }

    func reserve(operationID: String, estimatedCost: LedgerMoney, at: Date = .now) -> PartnerQuotaDecision {
        if let existing = operationDecisions[operationID] { return existing }
        let valid = policy.version > 0 && policy.periodStart < policy.periodEnd &&
            policy.periodStart <= at && at < policy.periodEnd && policy.maximumCalls >= 0 &&
            policy.maximumCost.amount >= 0 && estimatedCost.amount >= 0 &&
            policy.maximumCost.currencyCode.uppercased() == estimatedCost.currencyCode.uppercased() &&
            !operationID.isEmpty && !policy.scopeID.isEmpty
        let decision: PartnerQuotaDecision
        if !valid { decision = .denied(.invalidPolicy) }
        else if calls + 1 > policy.maximumCalls { decision = .denied(.callLimit) }
        else if cost + estimatedCost.amount > policy.maximumCost.amount { decision = .denied(.costLimit) }
        else { calls += 1; cost += estimatedCost.amount; decision = .allowed }
        operationDecisions[operationID] = decision
        audit.append(.init(sequence: audit.count + 1, operationID: operationID, scopeID: policy.scopeID,
                           decision: decision, requestedCost: estimatedCost, occurredAt: at))
        return decision
    }

    func usage() -> (calls: Int, cost: Decimal) { (calls, cost) }
    func auditTrail() -> [PartnerQuotaAuditEvent] { audit }
}
