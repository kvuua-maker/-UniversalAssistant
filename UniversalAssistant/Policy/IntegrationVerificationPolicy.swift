import Foundation

enum VerificationEvidenceLevel: Int, Codable, Comparable, Sendable {
    case e0, e1, e2, e3, e4, e5, e6
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum CanonicalRequirementStatus: String, Codable, Sendable {
    case notImplemented = "NOT_IMPLEMENTED"
    case implementedUnverified = "IMPLEMENTED_UNVERIFIED"
    case verifiedLocal = "VERIFIED_LOCAL"
    case readyForLiveVerification = "READY_FOR_LIVE_VERIFICATION"
    case verifiedLive = "VERIFIED_LIVE"
    case notApplicableVerified = "NOT_APPLICABLE_VERIFIED"
}

struct ExternalVerificationDependency: Equatable, Sendable {
    let missingDependency: String
    let dependencyOwner: String
    let requiredLiveAction: String
    let expectedResult: String

    var isSpecific: Bool {
        [missingDependency, dependencyOwner, requiredLiveAction, expectedResult]
            .allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

struct IntegrationVerificationEvidence: Sendable {
    let requirementID: String
    let provider: String
    let capability: String
    let environment: String
    let testType: String
    let dateAndBuild: String
    let result: String
    let nonSensitiveReference: String
    let level: VerificationEvidenceLevel
    let isExternalCapability: Bool
    let requiresPhysicalDevice: Bool
    let containsSensitiveEvidence: Bool
    let dependency: ExternalVerificationDependency?
}

enum IntegrationVerificationViolation: String, Equatable, Sendable {
    case incompleteEvidence
    case sensitiveEvidence
    case localEvidenceBelowE3
    case externalLiveEvidenceBelowE4
    case deviceEvidenceBelowE5
    case missingSpecificExternalDependency
    case dependencyPresentForVerifiedLive
}

struct IntegrationVerificationPolicy: Sendable {
    func violations(
        status: CanonicalRequirementStatus,
        evidence: IntegrationVerificationEvidence
    ) -> Set<IntegrationVerificationViolation> {
        var result: Set<IntegrationVerificationViolation> = []
        let requiredText = [
            evidence.requirementID, evidence.provider, evidence.capability,
            evidence.environment, evidence.testType, evidence.dateAndBuild,
            evidence.result, evidence.nonSensitiveReference
        ]
        if requiredText.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            result.insert(.incompleteEvidence)
        }
        if evidence.containsSensitiveEvidence { result.insert(.sensitiveEvidence) }

        switch status {
        case .verifiedLocal:
            if evidence.level < .e3 { result.insert(.localEvidenceBelowE3) }
        case .readyForLiveVerification:
            if evidence.level < .e3 { result.insert(.localEvidenceBelowE3) }
            if evidence.dependency?.isSpecific != true {
                result.insert(.missingSpecificExternalDependency)
            }
        case .verifiedLive:
            if evidence.isExternalCapability && evidence.level < .e4 {
                result.insert(.externalLiveEvidenceBelowE4)
            }
            if evidence.requiresPhysicalDevice && evidence.level < .e5 {
                result.insert(.deviceEvidenceBelowE5)
            }
            if evidence.dependency != nil { result.insert(.dependencyPresentForVerifiedLive) }
        case .notApplicableVerified:
            if evidence.level < .e1 { result.insert(.incompleteEvidence) }
        case .notImplemented, .implementedUnverified:
            break
        }
        return result
    }

    func canClaim(
        _ status: CanonicalRequirementStatus,
        evidence: IntegrationVerificationEvidence
    ) -> Bool {
        violations(status: status, evidence: evidence).isEmpty
    }
}
