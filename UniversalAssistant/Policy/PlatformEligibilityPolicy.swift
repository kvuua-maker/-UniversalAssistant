import Foundation

enum RestrictedPlatformCapability: String, Sendable { case carPlayAudio, carPlayCommunication, carPlayNavigation, healthKit, financialAccounts, governmentIdentity }
enum PlatformCapabilityDecision: Equatable, Sendable { case allowed; case ownerApprovalRequired(reason: String); case excluded(reason: String) }

struct PlatformEligibilityContext: Sendable {
    let appleManagedEntitlements: Set<String>
    let ownerApprovedCapabilities: Set<RestrictedPlatformCapability>
    let concreteFeatureRequirementIDs: Set<String>
}

struct PlatformEligibilityPolicy: Sendable {
    func decision(_ capability: RestrictedPlatformCapability, context: PlatformEligibilityContext) -> PlatformCapabilityDecision {
        switch capability {
        case .carPlayAudio, .carPlayCommunication, .carPlayNavigation:
            let entitlement = switch capability {
            case .carPlayAudio: "com.apple.developer.carplay-audio"
            case .carPlayCommunication: "com.apple.developer.carplay-communication"
            case .carPlayNavigation: "com.apple.developer.carplay-maps"
            default: ""
            }
            guard context.ownerApprovedCapabilities.contains(capability) else { return .ownerApprovalRequired(reason: "owner_category_decision_required") }
            guard context.appleManagedEntitlements.contains(entitlement) else { return .ownerApprovalRequired(reason: "apple_managed_entitlement_required") }
            return .allowed
        case .healthKit:
            return context.ownerApprovedCapabilities.contains(.healthKit) && !context.concreteFeatureRequirementIDs.isEmpty
                ? .allowed : .excluded(reason: "healthkit_out_of_v1_without_explicit_feature")
        case .financialAccounts, .governmentIdentity:
            return context.ownerApprovedCapabilities.contains(capability) && !context.concreteFeatureRequirementIDs.isEmpty
                ? .allowed : .excluded(reason: "sensitive_scope_requires_explicit_owner_requirement")
        }
    }
}
