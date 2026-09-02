import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Capability evidence governance") struct CapabilityEvidenceGovernanceTests {
    private func contract(route: [String] = ["user", "router", "gmail", "provider"],
                          evidence: VerificationEvidenceLevel = .e4,
                          failures: [String] = ["timeout", "revoked auth", "duplicate idempotency key"]) -> ProviderCapabilityContract {
        .init(requirementIDs: ["MS-932"], provider: "Gmail", capability: "SEND",
              examples: ["reply to this email"], requiredInputs: ["message ID", "body"],
              selectedPath: "official Gmail API", accessRequirements: ["OAuth send scope"],
              expectedRealResult: "provider message ID and read-back",
              acceptance: .init(userAction: "confirm reply", inputEntities: ["message ID", "body"],
                productionRoute: route, depth: .writeAction, authorization: "OAuth",
                expectedRealResult: "sent message", measurableSuccessEvidence: "provider ID plus read-back",
                failureCases: failures, fallback: "truthful unavailable result",
                privacyHandling: "minimum message fields; no credential logging",
                requiredEnvironment: "controlled provider account", requiredEvidence: evidence,
                stopCondition: "E4 send and read-back pass"),
              deviceTestRequired: false, idempotencyRequired: true, availability: .availableNow)
    }

    @Test func realExternalCapabilityRequiresCompleteE4Contract() {
        #expect(CapabilityEvidenceGovernance().violations(contract()).isEmpty)
        #expect(CapabilityEvidenceGovernance().violations(contract(route: ["mock"], evidence: .e3, failures: ["timeout"])) == [.fakeProductionRoute, .missingIdempotency, .insufficientEvidence])
    }

    @Test func transitionsCannotSkipOrOverclaimEvidence() {
        let gate = EvidenceStatusTransitionGate()
        #expect(!gate.allows(from: .implemented, to: .testedVerified, evidence: .e6, external: true, device: false))
        #expect(!gate.allows(from: .implemented, to: .integrated, evidence: .e3, external: true, device: false))
        #expect(gate.allows(from: .implemented, to: .integrated, evidence: .e4, external: true, device: false))
        #expect(!gate.allows(from: .fullyTested, to: .done, evidence: .e4, external: true, device: true))
        #expect(gate.allows(from: .fullyTested, to: .done, evidence: .e5, external: true, device: true))
        #expect(!gate.allows(from: .implemented, to: .blocked, evidence: .e2, external: false, device: false))
        #expect(gate.allows(from: .implemented, to: .blocked, evidence: .e2, external: false, device: false, exactBlocker: "OAuth owner grant"))
    }

    @Test func scopePackRoundTripsWithoutWeakeningSource() throws {
        let pack = RequirementScopePack(taskID: "M12-GMAIL-SEND", requirementIDs: ["MS-932", "MS-1380"],
            capability: "SEND", selectedPath: "official Gmail API",
            feasibilityDecision: .needsOwnerAccessForProof, integrationDepth: .writeAction,
            acceptanceContractReference: "docs/M12_GMAIL_EMAIL_INTEGRATION_CORE.md",
            requiredTestsAndEvidence: ["E3 failure tests", "E4 controlled send/read-back"],
            dependencies: ["OAuth account"], failureCases: ["revoked auth", "timeout"],
            stopCondition: "local implementation E3 and exact E4 queue item")
        #expect(try JSONDecoder().decode(RequirementScopePack.self, from: JSONEncoder().encode(pack)) == pack)
    }
}
