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
    let languageCodes: Set<String>
    let minimumAppVersion: String?

    init(feature: PartnerFeature, enabled: Bool, countryCodes: Set<String>, categories: Set<String>, languageCodes: Set<String> = [], minimumAppVersion: String? = nil) {
        self.feature = feature; self.enabled = enabled; self.countryCodes = countryCodes
        self.categories = categories; self.languageCodes = languageCodes; self.minimumAppVersion = minimumAppVersion
    }

    private enum CodingKeys: String, CodingKey { case feature, enabled, countryCodes, categories, languageCodes, minimumAppVersion }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        feature = try values.decode(PartnerFeature.self, forKey: .feature)
        enabled = try values.decode(Bool.self, forKey: .enabled)
        countryCodes = try values.decode(Set<String>.self, forKey: .countryCodes)
        categories = try values.decode(Set<String>.self, forKey: .categories)
        languageCodes = try values.decodeIfPresent(Set<String>.self, forKey: .languageCodes) ?? []
        minimumAppVersion = try values.decodeIfPresent(String.self, forKey: .minimumAppVersion)
    }
}

struct RemoteProviderRule: Equatable, Codable, Sendable {
    let providerID: String
    let enabled: Bool
    let priority: Int
    let timeoutMilliseconds: Int
    let countryCodes: Set<String>
    let emergencyDisabled: Bool
}

struct PartnerRuntimePolicySnapshot: Equatable, Codable, Sendable {
    let version: Int
    let effectiveFrom: Date
    let expiresAt: Date
    let rules: [PartnerFeatureRule]
    let sourceReference: String
    let providerRules: [RemoteProviderRule]

    init(version: Int, effectiveFrom: Date, expiresAt: Date, rules: [PartnerFeatureRule], sourceReference: String, providerRules: [RemoteProviderRule] = []) {
        self.version = version; self.effectiveFrom = effectiveFrom; self.expiresAt = expiresAt
        self.rules = rules; self.sourceReference = sourceReference; self.providerRules = providerRules
    }

    private enum CodingKeys: String, CodingKey { case version, effectiveFrom, expiresAt, rules, sourceReference, providerRules }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        effectiveFrom = try values.decode(Date.self, forKey: .effectiveFrom)
        expiresAt = try values.decode(Date.self, forKey: .expiresAt)
        rules = try values.decode([PartnerFeatureRule].self, forKey: .rules)
        sourceReference = try values.decode(String.self, forKey: .sourceReference)
        providerRules = try values.decodeIfPresent([RemoteProviderRule].self, forKey: .providerRules) ?? []
    }
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
              Set(snapshot.rules.map(\.feature)).count == snapshot.rules.count,
              Set(snapshot.providerRules.map(\.providerID)).count == snapshot.providerRules.count,
              snapshot.providerRules.allSatisfy(Self.validProviderRule),
              snapshot.rules.allSatisfy(Self.validFeatureRule) else {
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
                   languageCode: String = "", appVersion: String = "",
                   now: Date = .now) -> Bool {
        guard let current, current.effectiveFrom <= now, now < current.expiresAt,
              let rule = current.rules.first(where: { $0.feature == feature }), rule.enabled else { return false }
        let countryAllowed = rule.countryCodes.isEmpty || rule.countryCodes.contains(countryCode.uppercased())
        let categoryAllowed = rule.categories.isEmpty || rule.categories.contains(category.lowercased())
        let languageAllowed = rule.languageCodes.isEmpty || rule.languageCodes.contains(languageCode.lowercased())
        let versionAllowed = rule.minimumAppVersion.map { Self.compareVersions(appVersion, $0) >= 0 } ?? true
        return countryAllowed && categoryAllowed && languageAllowed && versionAllowed
    }

    func providers(countryCode: String, now: Date = .now) -> [RemoteProviderRule] {
        guard let current, current.effectiveFrom <= now, now < current.expiresAt else { return [] }
        return current.providerRules.filter {
            $0.enabled && !$0.emergencyDisabled && ($0.countryCodes.isEmpty || $0.countryCodes.contains(countryCode.uppercased()))
        }.sorted { $0.priority == $1.priority ? $0.providerID < $1.providerID : $0.priority < $1.priority }
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

    private static func validProviderRule(_ rule: RemoteProviderRule) -> Bool {
        !rule.providerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && rule.priority >= 0 && (100...30_000).contains(rule.timeoutMilliseconds)
    }

    private static func validFeatureRule(_ rule: PartnerFeatureRule) -> Bool {
        rule.minimumAppVersion.map { !$0.isEmpty && $0.split(separator: ".").allSatisfy { Int($0) != nil } } ?? true
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> Int {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }, right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0, r = index < right.count ? right[index] : 0
            if l != r { return l < r ? -1 : 1 }
        }
        return 0
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

enum ProviderCallOutcome: String, Codable, Sendable { case succeeded, failed, rateLimited, cancelled }

struct ProviderCostUsage: Equatable, Sendable {
    let providerID: String
    let requestCount: Int
    let allowedCount: Int
    let deniedCount: Int
    let rateLimitedCount: Int
    let failureCount: Int
    let cacheHitCount: Int
    let estimatedCost: LedgerMoney
    var failureRate: Decimal { requestCount == 0 ? 0 : Decimal(failureCount) / Decimal(requestCount) }
    var cacheEffectiveness: Decimal { requestCount == 0 ? 0 : Decimal(cacheHitCount) / Decimal(requestCount) }
}

/// Central non-AI API budget gate. It reuses the exact-money quota ledger and stores no payload or user identifier.
actor CostQuotaManager {
    private struct MutableUsage {
        var requests = 0, allowed = 0, denied = 0, rateLimited = 0, failures = 0, cacheHits = 0
        var cost = Decimal.zero
        var observed: Set<String> = []
    }
    private let ledgers: [String: PartnerCostQuotaLedger]
    private let currencies: [String: String]
    private var usage: [String: MutableUsage] = [:]

    init(policiesByProvider: [String: PartnerQuotaPolicy]) {
        ledgers = policiesByProvider.mapValues { PartnerCostQuotaLedger(policy: $0) }
        currencies = policiesByProvider.mapValues { $0.maximumCost.currencyCode.uppercased() }
    }

    func reserve(providerID: String, operationID: String, estimatedCost: LedgerMoney, cacheHit: Bool = false, at: Date = .now) async -> PartnerQuotaDecision {
        guard let ledger = ledgers[providerID] else { return .denied(.invalidPolicy) }
        var value = usage[providerID, default: MutableUsage()]
        let observationKey = "reserve:\(operationID)"
        if value.observed.contains(observationKey) { return await ledger.reserve(operationID: operationID, estimatedCost: estimatedCost, at: at) }
        value.observed.insert(observationKey); value.requests += 1
        if cacheHit { value.cacheHits += 1; value.allowed += 1; usage[providerID] = value; return .allowed }
        let decision = await ledger.reserve(operationID: operationID, estimatedCost: estimatedCost, at: at)
        switch decision { case .allowed: value.allowed += 1; value.cost += estimatedCost.amount; case .denied: value.denied += 1 }
        usage[providerID] = value
        return decision
    }

    func recordOutcome(providerID: String, operationID: String, outcome: ProviderCallOutcome) {
        var value = usage[providerID, default: MutableUsage()]
        guard value.observed.insert("outcome:\(operationID)").inserted else { return }
        if outcome == .failed { value.failures += 1 }
        if outcome == .rateLimited { value.rateLimited += 1; value.failures += 1 }
        usage[providerID] = value
    }

    func snapshot(providerID: String) -> ProviderCostUsage? {
        guard let currency = currencies[providerID] else { return nil }
        let value = usage[providerID, default: MutableUsage()]
        return .init(providerID: providerID, requestCount: value.requests, allowedCount: value.allowed, deniedCount: value.denied, rateLimitedCount: value.rateLimited, failureCount: value.failures, cacheHitCount: value.cacheHits, estimatedCost: .init(amount: value.cost, currencyCode: currency))
    }
}
