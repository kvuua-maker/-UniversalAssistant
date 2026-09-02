import Testing
@testable import UniversalAssistantServer

@Suite("App version support and forced update policy")
struct AppVersionSupportPolicyTests {
    @Test func currentAndSupportedPriorVersionsAreNeverForcedForConvenience() throws {
        let policy = try AppVersionSupportPolicy(
            current: SemanticAppVersion("3.4.0"),
            minimumSupported: SemanticAppVersion("3.2.0"),
            supportedPriorMinorVersions: 2,
            forcedUpdateReason: .criticalCompatibility
        )
        #expect(policy.evaluate(try SemanticAppVersion("3.4")) == .supported)
        #expect(
            policy.evaluate(try SemanticAppVersion("3.3.1"))
                == .updateAvailable(current: try SemanticAppVersion("3.4.0"))
        )
        #expect(
            policy.evaluate(try SemanticAppVersion("3.2.0"))
                == .updateAvailable(current: try SemanticAppVersion("3.4.0"))
        )
    }

    @Test func belowMinimumIsForcedOnlyWithCanonicalReason() throws {
        let minimum = try SemanticAppVersion("3.2.0")
        for reason in [ForcedUpdateReason.security, .legal, .criticalCompatibility] {
            let policy = try AppVersionSupportPolicy(
                current: SemanticAppVersion("3.4.0"),
                minimumSupported: minimum,
                forcedUpdateReason: reason
            )
            #expect(
                policy.evaluate(try SemanticAppVersion("3.1.9"))
                    == .updateRequired(minimum: minimum, reason: reason)
            )
        }
    }

    @Test func policyRejectsSilentConvenienceCutoffAndMalformedVersions() throws {
        #expect(throws: AppVersionPolicyError.unjustifiedForcedUpdate) {
            try AppVersionSupportPolicy(
                current: SemanticAppVersion("2.0.0"),
                minimumSupported: SemanticAppVersion("1.9.0")
            )
        }
        #expect(throws: AppVersionPolicyError.invalidVersion) {
            try SemanticAppVersion("latest")
        }
    }
}
