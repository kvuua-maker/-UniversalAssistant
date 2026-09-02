import Testing
@testable import UniversalAssistant

@Suite("Platform eligibility and sensitive data") struct PlatformEligibilityPolicyTests {
    let policy = PlatformEligibilityPolicy()
    @Test func carPlayFailsClosedWithoutOwnerAndAppleManagedEntitlement() {
        let empty = PlatformEligibilityContext(appleManagedEntitlements: [], ownerApprovedCapabilities: [], concreteFeatureRequirementIDs: [])
        #expect(policy.decision(.carPlayNavigation, context: empty) == .ownerApprovalRequired(reason: "owner_category_decision_required"))
        let ownerOnly = PlatformEligibilityContext(appleManagedEntitlements: [], ownerApprovedCapabilities: [.carPlayNavigation], concreteFeatureRequirementIDs: ["MS-978"])
        #expect(policy.decision(.carPlayNavigation, context: ownerOnly) == .ownerApprovalRequired(reason: "apple_managed_entitlement_required"))
    }
    @Test func exactApprovedCarPlayCategoryCanBeEnabledWithoutGeneralPurposeUI() {
        let context = PlatformEligibilityContext(appleManagedEntitlements: ["com.apple.developer.carplay-maps"], ownerApprovedCapabilities: [.carPlayNavigation], concreteFeatureRequirementIDs: ["MS-978"])
        #expect(policy.decision(.carPlayNavigation, context: context) == .allowed)
        #expect(policy.decision(.carPlayAudio, context: context) != .allowed)
    }
    @Test func healthFinancialAndIdentityScopesRemainExcludedByDefault() {
        let context = PlatformEligibilityContext(appleManagedEntitlements: [], ownerApprovedCapabilities: [], concreteFeatureRequirementIDs: [])
        #expect(policy.decision(.healthKit, context: context) == .excluded(reason: "healthkit_out_of_v1_without_explicit_feature"))
        #expect(policy.decision(.financialAccounts, context: context) == .excluded(reason: "sensitive_scope_requires_explicit_owner_requirement"))
        #expect(policy.decision(.governmentIdentity, context: context) == .excluded(reason: "sensitive_scope_requires_explicit_owner_requirement"))
    }
}
