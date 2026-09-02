import Foundation

enum CanonicalIntegrationDepth: Int, Codable, Comparable, Sendable {
    case unsupported, open, contextHandoff, readSearch, writeAction, transaction, monitorProactive
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum CapabilityAvailability: String, Codable, Sendable {
    case availableNow = "AVAILABLE_NOW"
    case ownerActionRequired = "OWNER_ACTION_REQUIRED"
    case partnerApprovalRequired = "PARTNER_APPROVAL_REQUIRED"
    case paidAccessRequired = "PAID_ACCESS_REQUIRED"
    case unsupported = "UNSUPPORTED"
}

struct IntegrationAcceptanceContract: Codable, Equatable, Sendable {
    let userAction: String
    let inputEntities: [String]
    let productionRoute: [String]
    let depth: CanonicalIntegrationDepth
    let authorization: String
    let expectedRealResult: String
    let measurableSuccessEvidence: String
    let failureCases: [String]
    let fallback: String
    let privacyHandling: String
    let requiredEnvironment: String
    let requiredEvidence: VerificationEvidenceLevel
    let stopCondition: String
}

struct ProviderCapabilityContract: Codable, Equatable, Sendable {
    let requirementIDs: [String]
    let provider: String
    let capability: String
    let examples: [String]
    let requiredInputs: [String]
    let selectedPath: String
    let accessRequirements: [String]
    let expectedRealResult: String
    let acceptance: IntegrationAcceptanceContract
    let deviceTestRequired: Bool
    let idempotencyRequired: Bool
    let availability: CapabilityAvailability
}

struct RequirementScopePack: Codable, Equatable, Sendable {
    let taskID: String
    let requirementIDs: [String]
    let capability: String
    let selectedPath: String
    let feasibilityDecision: FeasibilityGateState
    let integrationDepth: CanonicalIntegrationDepth
    let acceptanceContractReference: String
    let requiredTestsAndEvidence: [String]
    let dependencies: [String]
    let failureCases: [String]
    let stopCondition: String
}

enum CapabilityContractViolation: String, Equatable, Sendable {
    case incompleteContract, missingFailureBehavior, missingIdempotency, insufficientEvidence
    case fakeProductionRoute, missingStopCondition
}

struct CapabilityEvidenceGovernance: Sendable {
    func violations(_ contract: ProviderCapabilityContract) -> Set<CapabilityContractViolation> {
        var result: Set<CapabilityContractViolation> = []
        let text = [contract.provider, contract.capability, contract.selectedPath,
                    contract.expectedRealResult, contract.acceptance.userAction,
                    contract.acceptance.authorization, contract.acceptance.measurableSuccessEvidence,
                    contract.acceptance.fallback, contract.acceptance.privacyHandling,
                    contract.acceptance.requiredEnvironment]
        if contract.requirementIDs.isEmpty || contract.examples.isEmpty || contract.requiredInputs.isEmpty ||
            contract.acceptance.inputEntities.isEmpty || contract.acceptance.productionRoute.isEmpty ||
            text.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            result.insert(.incompleteContract)
        }
        if contract.acceptance.failureCases.isEmpty { result.insert(.missingFailureBehavior) }
        if contract.idempotencyRequired && !contract.acceptance.failureCases.contains(where: {
            $0.localizedCaseInsensitiveContains("duplicate") || $0.localizedCaseInsensitiveContains("idempot")
        }) { result.insert(.missingIdempotency) }
        if contract.acceptance.requiredEvidence < .e4 &&
            contract.acceptance.depth >= .readSearch && contract.availability == .availableNow {
            result.insert(.insufficientEvidence)
        }
        if contract.acceptance.productionRoute.contains(where: {
            ["mock", "fixture", "demo", "fake"].contains($0.lowercased())
        }) { result.insert(.fakeProductionRoute) }
        if contract.acceptance.stopCondition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.insert(.missingStopCondition)
        }
        return result
    }
}

enum EvidenceTransitionState: String, Codable, Sendable {
    case planned, feasibilityPass, implemented, integrated, testedVerified
    case deviceTestRequired, fullyTested, done, blocked
}

struct EvidenceStatusTransitionGate: Sendable {
    func allows(from: EvidenceTransitionState, to: EvidenceTransitionState,
                evidence: VerificationEvidenceLevel, external: Bool, device: Bool,
                exactBlocker: String? = nil) -> Bool {
        if to == .blocked { return !(exactBlocker ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let order: [EvidenceTransitionState] = [.planned, .feasibilityPass, .implemented, .integrated,
            .testedVerified, .deviceTestRequired, .fullyTested, .done]
        guard let source = order.firstIndex(of: from), let target = order.firstIndex(of: to),
              target == source + 1 else { return false }
        if to == .integrated && external && evidence < .e4 { return false }
        if to == .fullyTested && device && evidence < .e5 { return false }
        if to == .done && ((external && evidence < .e4) || (device && evidence < .e5)) { return false }
        return true
    }
}
