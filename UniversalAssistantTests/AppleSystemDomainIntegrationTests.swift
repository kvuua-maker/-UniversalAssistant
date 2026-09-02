import Testing
@testable import UniversalAssistant

@Suite("Apple system domain audit") struct AppleSystemDomainIntegrationTests {
    @Test func everyCanonicalDomainHasExplicitImplementedDepthAndLimit() {
        #expect(Set(AppleSystemDomainAudit.evidence.map(\.domain)) == Set(AppleSystemDomain.allCases))
        #expect(AppleSystemDomainAudit.evidence.allSatisfy { $0.implemented && !$0.deepestPublicBehavior.isEmpty })
    }

    @Test func restrictedDomainsNeverClaimPrivateAccess() throws {
        for domain in [AppleSystemDomain.mail, .messages, .photos, .files, .notes, .clock, .search] {
            let evidence = try #require(AppleSystemDomainAudit.evidence.first { $0.domain == domain })
            #expect(evidence.limitation != nil)
        }
    }

    @Test func simulatorDoesNotPretendCameraCaptureIsAvailable() {
#if targetEnvironment(simulator)
        #expect(!SystemCameraCapture.isAvailable)
#endif
    }
}
