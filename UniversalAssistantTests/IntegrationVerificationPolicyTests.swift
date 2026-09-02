import Testing
@testable import UniversalAssistant

@Suite("Real integration evidence policy")
struct IntegrationVerificationPolicyTests {
    let policy = IntegrationVerificationPolicy()

    private func evidence(
        level: VerificationEvidenceLevel,
        external: Bool = true,
        device: Bool = false,
        sensitive: Bool = false,
        dependency: ExternalVerificationDependency? = nil
    ) -> IntegrationVerificationEvidence {
        IntegrationVerificationEvidence(
            requirementID: "MS-987",
            provider: "Controlled provider",
            capability: "authorized search",
            environment: "sandbox account",
            testType: "read and zero-result",
            dateAndBuild: "2026-09-02 / test-build",
            result: "expected controlled object observed",
            nonSensitiveReference: "verification-run-17",
            level: level,
            isExternalCapability: external,
            requiresPhysicalDevice: device,
            containsSensitiveEvidence: sensitive,
            dependency: dependency
        )
    }

    @Test func mockOrInternalEvidenceCannotPromoteExternalCapabilityToVerifiedLive() {
        let violations = policy.violations(status: .verifiedLive, evidence: evidence(level: .e3))
        #expect(violations.contains(.externalLiveEvidenceBelowE4))
        #expect(!policy.canClaim(.verifiedLive, evidence: evidence(level: .e3)))
    }

    @Test func physicalCapabilityRequiresObservedE5Evidence() {
        #expect(policy.violations(status: .verifiedLive, evidence: evidence(level: .e4, device: true))
            .contains(.deviceEvidenceBelowE5))
        #expect(policy.canClaim(.verifiedLive, evidence: evidence(level: .e5, device: true)))
    }

    @Test func readyForLiveRequiresCompleteSpecificHandoff() {
        #expect(policy.violations(status: .readyForLiveVerification, evidence: evidence(level: .e3))
            .contains(.missingSpecificExternalDependency))
        let dependency = ExternalVerificationDependency(
            missingDependency: "Owner test account OAuth grant",
            dependencyOwner: "Owner",
            requiredLiveAction: "Authorize and search for the controlled record",
            expectedResult: "Exact controlled record is returned"
        )
        #expect(policy.canClaim(.readyForLiveVerification, evidence: evidence(level: .e3, dependency: dependency)))
    }

    @Test func sensitiveEvidenceIsRejected() {
        #expect(policy.violations(status: .verifiedLive, evidence: evidence(level: .e4, sensitive: true))
            .contains(.sensitiveEvidence))
    }
}
