import Foundation

enum PartnerRiskSignal: String, Codable, Hashable, Sendable {
    case duplicateAttribution
    case duplicateExternalTransaction
    case suspectedSelfReferral
    case excessiveConversionVelocity
    case excessiveRefundRatio
    case commissionExceedsGross
    case webhookReplay
}
enum PartnerRiskDisposition: String, Codable, Sendable { case allow, reviewRequired, rejectDuplicate }

struct PartnerRiskInput: Sendable {
    let partnerID: UUID
    let attributionID: UUID
    let externalTransactionID: String
    let pseudonymousReference: String?
    let partnerControlledReferences: Set<String>
    let recentConversionCount: Int
    let recentRefundCount: Int
    let grossAmount: Decimal
    let commissionAmount: Decimal
    let duplicateAttribution: Bool
    let duplicateExternalTransaction: Bool
    let webhookReplay: Bool
}

struct PartnerRiskAssessment: Equatable, Sendable {
    let signals: Set<PartnerRiskSignal>
    let disposition: PartnerRiskDisposition
}

struct PartnerRiskAuditEvent: Equatable, Sendable {
    let sequence: Int
    let partnerID: UUID
    let attributionID: UUID
    let signals: Set<PartnerRiskSignal>
    let disposition: PartnerRiskDisposition
    let policyVersion: String
    let assessedAt: Date
}

struct PartnerRiskPolicy: Equatable, Sendable {
    let version: String
    let maximumConversionsPerWindow: Int
    let refundReviewRatio: Decimal
}

actor PartnerFraudControlEngine {
    private let policy: PartnerRiskPolicy
    private var audit: [PartnerRiskAuditEvent] = []

    init(policy: PartnerRiskPolicy) { self.policy = policy }

    func assess(_ input: PartnerRiskInput, at: Date = .now) -> PartnerRiskAssessment {
        var signals: Set<PartnerRiskSignal> = []
        if input.duplicateAttribution { signals.insert(.duplicateAttribution) }
        if input.duplicateExternalTransaction { signals.insert(.duplicateExternalTransaction) }
        if input.webhookReplay { signals.insert(.webhookReplay) }
        if let reference = input.pseudonymousReference,
           input.partnerControlledReferences.contains(reference) { signals.insert(.suspectedSelfReferral) }
        if input.recentConversionCount > policy.maximumConversionsPerWindow { signals.insert(.excessiveConversionVelocity) }
        if input.recentConversionCount > 0,
           Decimal(input.recentRefundCount) / Decimal(input.recentConversionCount) > policy.refundReviewRatio {
            signals.insert(.excessiveRefundRatio)
        }
        if input.commissionAmount > input.grossAmount { signals.insert(.commissionExceedsGross) }
        let duplicates: Set<PartnerRiskSignal> = [.duplicateAttribution, .duplicateExternalTransaction, .webhookReplay]
        let disposition: PartnerRiskDisposition = !signals.isDisjoint(with: duplicates)
            ? .rejectDuplicate : (signals.isEmpty ? .allow : .reviewRequired)
        let result = PartnerRiskAssessment(signals: signals, disposition: disposition)
        audit.append(.init(sequence: audit.count + 1, partnerID: input.partnerID,
                           attributionID: input.attributionID, signals: signals,
                           disposition: disposition, policyVersion: policy.version, assessedAt: at))
        return result
    }

    func auditTrail() -> [PartnerRiskAuditEvent] { audit }
}
