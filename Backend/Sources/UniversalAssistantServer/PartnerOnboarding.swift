import Foundation

enum PartnerOnboardingState: String, Codable, Sendable {
    case draft = "DRAFT"
    case submitted = "SUBMITTED"
    case verificationRequired = "VERIFICATION_REQUIRED"
    case underReview = "UNDER_REVIEW"
    case technicalValidation = "TECHNICAL_VALIDATION"
    case contractRequired = "CONTRACT_REQUIRED"
    case approved = "APPROVED"
    case active = "ACTIVE"
    case suspended = "SUSPENDED"
    case rejected = "REJECTED"
    case terminated = "TERMINATED"
}

enum PartnerIntegrationLevel: String, Codable, Sendable {
    case basicProfile = "L1_BASIC_PROFILE"
    case feedCatalog = "L2_FEED_CATALOG"
    case affiliateDeepLink = "L3_AFFILIATE_DEEP_LINK"
    case fullAPI = "L4_FULL_API"

    var requiresTechnicalValidation: Bool { self != .basicProfile }
}

struct PartnerApplicationDraft: Equatable, Codable, Sendable {
    let legalName: String
    let registrationReference: String
    let contactEmail: String
    let category: String
    let countryCode: String
    let integrationLevel: PartnerIntegrationLevel
}

struct PartnerVerificationEvidence: Equatable, Codable, Sendable {
    let evidenceID: String
    let evidenceType: String
    let verifiedAt: Date
    let verifierReference: String
}

struct PartnerAuditEvent: Equatable, Codable, Sendable {
    let sequence: Int
    let from: PartnerOnboardingState
    let to: PartnerOnboardingState
    let actorReference: String
    let reasonCode: String
    let occurredAt: Date
}

struct PartnerOnboardingRecord: Equatable, Codable, Sendable {
    let partnerID: UUID
    var draft: PartnerApplicationDraft
    var state: PartnerOnboardingState
    var verificationEvidence: [PartnerVerificationEvidence]
    var technicalValidationPassed: Bool
    var agreementReference: String?
    var approvalRecorded: Bool
    var auditTrail: [PartnerAuditEvent]
}

enum PartnerOnboardingError: Error, Equatable, Sendable {
    case invalidApplication
    case invalidEvidence
    case invalidTransition
    case verificationRequired
    case technicalValidationRequired
    case contractRequired
    case approvalRequired
}

actor PartnerOnboardingService {
    private var records: [UUID: PartnerOnboardingRecord] = [:]

    func createDraft(_ draft: PartnerApplicationDraft) throws -> PartnerOnboardingRecord {
        guard Self.valid(draft) else { throw PartnerOnboardingError.invalidApplication }
        let record = PartnerOnboardingRecord(
            partnerID: UUID(), draft: draft, state: .draft, verificationEvidence: [],
            technicalValidationPassed: false, agreementReference: nil,
            approvalRecorded: false, auditTrail: []
        )
        records[record.partnerID] = record
        return record
    }

    func submit(_ partnerID: UUID, actor: String, at: Date = .now) throws -> PartnerOnboardingRecord {
        try transition(partnerID, to: .submitted, actor: actor, reason: "application_submitted", at: at)
    }

    func requireVerification(_ partnerID: UUID, actor: String, at: Date = .now) throws -> PartnerOnboardingRecord {
        try transition(partnerID, to: .verificationRequired, actor: actor, reason: "verification_required", at: at)
    }

    func addVerificationEvidence(
        _ evidence: PartnerVerificationEvidence, to partnerID: UUID,
        actor: String, at: Date = .now
    ) throws -> PartnerOnboardingRecord {
        guard Self.nonempty(evidence.evidenceID), Self.nonempty(evidence.evidenceType),
              Self.nonempty(evidence.verifierReference), evidence.verifiedAt <= at
        else { throw PartnerOnboardingError.invalidEvidence }
        var record = try existing(partnerID)
        guard record.state == .verificationRequired else { throw PartnerOnboardingError.invalidTransition }
        if !record.verificationEvidence.contains(where: { $0.evidenceID == evidence.evidenceID }) {
            record.verificationEvidence.append(evidence)
        }
        records[partnerID] = record
        return try transition(partnerID, to: .underReview, actor: actor, reason: "evidence_recorded", at: at)
    }

    func beginReview(_ partnerID: UUID, actor: String, at: Date = .now) throws -> PartnerOnboardingRecord {
        let record = try existing(partnerID)
        guard !record.verificationEvidence.isEmpty else { throw PartnerOnboardingError.verificationRequired }
        return try transition(partnerID, to: .underReview, actor: actor, reason: "review_started", at: at)
    }

    func beginTechnicalValidation(_ partnerID: UUID, actor: String, at: Date = .now) throws -> PartnerOnboardingRecord {
        try transition(partnerID, to: .technicalValidation, actor: actor, reason: "technical_validation_started", at: at)
    }

    func passTechnicalValidation(_ partnerID: UUID, actor: String, at: Date = .now) throws -> PartnerOnboardingRecord {
        var record = try existing(partnerID)
        guard record.state == .technicalValidation else { throw PartnerOnboardingError.invalidTransition }
        record.technicalValidationPassed = true
        records[partnerID] = record
        return try transition(partnerID, to: .contractRequired, actor: actor, reason: "technical_validation_passed", at: at)
    }

    func requireContract(_ partnerID: UUID, actor: String, at: Date = .now) throws -> PartnerOnboardingRecord {
        try transition(partnerID, to: .contractRequired, actor: actor, reason: "contract_required", at: at)
    }

    func recordAgreement(_ reference: String, for partnerID: UUID) throws -> PartnerOnboardingRecord {
        guard Self.nonempty(reference) else { throw PartnerOnboardingError.contractRequired }
        var record = try existing(partnerID)
        guard record.state == .contractRequired else { throw PartnerOnboardingError.invalidTransition }
        record.agreementReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        records[partnerID] = record
        return record
    }

    func approve(_ partnerID: UUID, actor: String, at: Date = .now) throws -> PartnerOnboardingRecord {
        var record = try existing(partnerID)
        guard !record.verificationEvidence.isEmpty else { throw PartnerOnboardingError.verificationRequired }
        guard !record.draft.integrationLevel.requiresTechnicalValidation || record.technicalValidationPassed
        else { throw PartnerOnboardingError.technicalValidationRequired }
        guard record.agreementReference != nil else { throw PartnerOnboardingError.contractRequired }
        record.approvalRecorded = true
        records[partnerID] = record
        return try transition(partnerID, to: .approved, actor: actor, reason: "approval_recorded", at: at)
    }

    func activate(_ partnerID: UUID, actor: String, at: Date = .now) throws -> PartnerOnboardingRecord {
        let record = try existing(partnerID)
        guard record.approvalRecorded else { throw PartnerOnboardingError.approvalRequired }
        guard !record.verificationEvidence.isEmpty else { throw PartnerOnboardingError.verificationRequired }
        return try transition(partnerID, to: .active, actor: actor, reason: "partner_activated", at: at)
    }

    func suspend(_ partnerID: UUID, actor: String, at: Date = .now) throws -> PartnerOnboardingRecord {
        try transition(partnerID, to: .suspended, actor: actor, reason: "partner_suspended", at: at)
    }

    func terminate(_ partnerID: UUID, actor: String, at: Date = .now) throws -> PartnerOnboardingRecord {
        try transition(partnerID, to: .terminated, actor: actor, reason: "partner_terminated", at: at)
    }

    func changeCriticalIdentity(
        _ draft: PartnerApplicationDraft, for partnerID: UUID,
        actor: String, at: Date = .now
    ) throws -> PartnerOnboardingRecord {
        guard Self.valid(draft) else { throw PartnerOnboardingError.invalidApplication }
        var record = try existing(partnerID)
        let previous = record.state
        record.draft = draft
        record.verificationEvidence = []
        record.approvalRecorded = false
        record.state = .verificationRequired
        record.auditTrail.append(.init(sequence: record.auditTrail.count + 1, from: previous,
                                       to: .verificationRequired, actorReference: actor,
                                       reasonCode: "critical_identity_changed", occurredAt: at))
        records[partnerID] = record
        return record
    }

    func record(_ partnerID: UUID) -> PartnerOnboardingRecord? { records[partnerID] }

    private func transition(
        _ partnerID: UUID, to next: PartnerOnboardingState,
        actor: String, reason: String, at: Date
    ) throws -> PartnerOnboardingRecord {
        var record = try existing(partnerID)
        guard Self.nonempty(actor), Self.allowed(record.state, next) else {
            throw PartnerOnboardingError.invalidTransition
        }
        record.auditTrail.append(.init(sequence: record.auditTrail.count + 1, from: record.state,
                                       to: next, actorReference: actor,
                                       reasonCode: reason, occurredAt: at))
        record.state = next
        records[partnerID] = record
        return record
    }

    private func existing(_ partnerID: UUID) throws -> PartnerOnboardingRecord {
        guard let record = records[partnerID] else { throw PartnerOnboardingError.invalidApplication }
        return record
    }

    private static func allowed(_ from: PartnerOnboardingState, _ to: PartnerOnboardingState) -> Bool {
        switch (from, to) {
        case (.draft, .submitted), (.submitted, .verificationRequired),
             (.submitted, .underReview), (.verificationRequired, .underReview),
             (.underReview, .technicalValidation), (.underReview, .contractRequired),
             (.technicalValidation, .contractRequired), (.contractRequired, .approved),
             (.approved, .active), (.active, .suspended), (.suspended, .active),
             (.submitted, .rejected), (.underReview, .rejected),
             (.active, .terminated), (.suspended, .terminated), (.approved, .terminated): return true
        default: return false
        }
    }

    private static func valid(_ draft: PartnerApplicationDraft) -> Bool {
        nonempty(draft.legalName) && nonempty(draft.registrationReference) &&
        nonempty(draft.contactEmail) && draft.contactEmail.contains("@") &&
        nonempty(draft.category) && draft.countryCode.count == 2
    }

    private static func nonempty(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
