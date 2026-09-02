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
}

actor PartnerRuntimePolicyStore {
    private var current: PartnerRuntimePolicySnapshot?

    func install(_ snapshot: PartnerRuntimePolicySnapshot) throws {
        guard snapshot.version > 0, snapshot.effectiveFrom < snapshot.expiresAt,
              !snapshot.sourceReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Set(snapshot.rules.map(\.feature)).count == snapshot.rules.count else {
            throw PartnerRuntimePolicyError.invalidSnapshot
        }
        guard current.map({ snapshot.version > $0.version }) ?? true else {
            throw PartnerRuntimePolicyError.staleVersion
        }
        current = snapshot
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
