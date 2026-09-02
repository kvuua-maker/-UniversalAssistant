import Foundation
import Testing
@testable import UniversalAssistantServer

private func partnerDraft(level: PartnerIntegrationLevel = .basicProfile) -> PartnerApplicationDraft {
    .init(legalName: "Local Bakery LLC", registrationReference: "REG-1",
          contactEmail: "owner@example.test", category: "restaurant",
          countryCode: "UA", integrationLevel: level)
}

private func evidence(at date: Date) -> PartnerVerificationEvidence {
    .init(evidenceID: "evidence-1", evidenceType: "business_registry",
          verifiedAt: date, verifierReference: "reviewer-1")
}

@Suite("Partner onboarding and verification")
struct PartnerOnboardingTests {
    @Test func submittedFormCannotBecomeActiveWithoutVerificationAndApproval() async throws {
        let service = PartnerOnboardingService()
        let draft = try await service.createDraft(partnerDraft())
        _ = try await service.submit(draft.partnerID, actor: "applicant")
        await #expect(throws: PartnerOnboardingError.approvalRequired) {
            try await service.activate(draft.partnerID, actor: "admin")
        }
    }

    @Test func completeBasicProfileFlowIsAuditedInOrder() async throws {
        let service = PartnerOnboardingService()
        let now = Date()
        let draft = try await service.createDraft(partnerDraft())
        _ = try await service.submit(draft.partnerID, actor: "applicant", at: now)
        _ = try await service.requireVerification(draft.partnerID, actor: "policy", at: now)
        _ = try await service.addVerificationEvidence(evidence(at: now), to: draft.partnerID, actor: "reviewer", at: now)
        _ = try await service.requireContract(draft.partnerID, actor: "commercial", at: now)
        _ = try await service.recordAgreement("agreement-v1", for: draft.partnerID)
        _ = try await service.approve(draft.partnerID, actor: "admin", at: now)
        let active = try await service.activate(draft.partnerID, actor: "admin", at: now)
        #expect(active.state == .active)
        #expect(active.auditTrail.map(\.sequence) == Array(1...6))
        #expect(active.auditTrail.last?.reasonCode == "partner_activated")
    }

    @Test func APIIntegrationRequiresTechnicalValidation() async throws {
        let service = PartnerOnboardingService()
        let now = Date()
        let draft = try await service.createDraft(partnerDraft(level: .fullAPI))
        _ = try await service.submit(draft.partnerID, actor: "applicant")
        _ = try await service.requireVerification(draft.partnerID, actor: "policy")
        _ = try await service.addVerificationEvidence(evidence(at: now), to: draft.partnerID, actor: "reviewer")
        _ = try await service.requireContract(draft.partnerID, actor: "commercial")
        _ = try await service.recordAgreement("agreement-v1", for: draft.partnerID)
        await #expect(throws: PartnerOnboardingError.technicalValidationRequired) {
            try await service.approve(draft.partnerID, actor: "admin")
        }
    }

    @Test func criticalIdentityChangeRevokesEvidenceAndApproval() async throws {
        let service = PartnerOnboardingService()
        let now = Date()
        let draft = try await service.createDraft(partnerDraft())
        _ = try await service.submit(draft.partnerID, actor: "applicant")
        _ = try await service.requireVerification(draft.partnerID, actor: "policy")
        _ = try await service.addVerificationEvidence(evidence(at: now), to: draft.partnerID, actor: "reviewer")
        let changed = try await service.changeCriticalIdentity(
            .init(legalName: "Renamed Bakery LLC", registrationReference: "REG-2",
                  contactEmail: "owner@example.test", category: "restaurant",
                  countryCode: "UA", integrationLevel: .basicProfile),
            for: draft.partnerID, actor: "applicant"
        )
        #expect(changed.state == .verificationRequired)
        #expect(changed.verificationEvidence.isEmpty)
        #expect(!changed.approvalRecorded)
        #expect(changed.auditTrail.last?.reasonCode == "critical_identity_changed")
    }
}
