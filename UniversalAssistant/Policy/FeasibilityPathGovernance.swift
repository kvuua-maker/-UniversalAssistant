import Foundation

enum FeasibilityGateState: String, Codable, Sendable {
    case passSelectedPath = "PASS_SELECTED_PATH"
    case externalBlocked = "EXTERNAL_BLOCKED"
    case unsupported = "UNSUPPORTED"
    case needsOwnerAccessForProof = "NEEDS_OWNER_ACCESS_FOR_PROOF"
}

enum AtomicTaskExitState: String, Codable, Sendable {
    case success = "SUCCESS"
    case externalBlocked = "EXTERNAL_BLOCKED"
    case unsupported = "UNSUPPORTED"
    case deviceTestRequired = "DEVICE_TEST_REQUIRED"
    case dependencyWait = "DEPENDENCY_WAIT"
}

struct FeasibilityCapabilityDecision: Codable, Equatable, Sendable {
    let taskID: String
    let capability: String
    let requiredActions: [String]
    let selectedPath: String
    let officialEvidence: [String]
    let accessRequirements: [String]
    let proofResult: String
    let state: FeasibilityGateState
    let recordedAt: Date
    let context: String
    let closed: Bool
}

enum FeasibilityGovernanceError: Error, Equatable {
    case invalidRecord
    case duplicateCapability
    case secondActivePath
    case closedWithoutPassingPath
    case reopenWithoutNewEvidence
}

actor FeasibilityPathRegistry {
    private let store: LocalStore
    private let fileName: String

    init(store: LocalStore = .shared, fileName: String = "feasibility-path-registry.json") {
        self.store = store
        self.fileName = fileName
    }

    func record(_ decision: FeasibilityCapabilityDecision) async throws {
        guard !decision.taskID.isEmpty, !decision.capability.isEmpty,
              !decision.requiredActions.isEmpty, !decision.selectedPath.isEmpty,
              !decision.officialEvidence.isEmpty, !decision.proofResult.isEmpty,
              !decision.context.isEmpty else { throw FeasibilityGovernanceError.invalidRecord }
        guard !decision.closed || decision.state == .passSelectedPath else {
            throw FeasibilityGovernanceError.closedWithoutPassingPath
        }
        var records = try await all()
        guard !records.contains(where: { $0.taskID == decision.taskID && $0.capability == decision.capability }) else {
            throw FeasibilityGovernanceError.duplicateCapability
        }
        guard !records.contains(where: { $0.taskID == decision.taskID && !$0.closed }) else {
            throw FeasibilityGovernanceError.secondActivePath
        }
        records.append(decision)
        try await store.save(records, as: fileName)
    }

    func reopen(taskID: String, capability: String, newEvidence: String) async throws {
        guard !newEvidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FeasibilityGovernanceError.reopenWithoutNewEvidence
        }
        var records = try await all()
        guard let index = records.firstIndex(where: { $0.taskID == taskID && $0.capability == capability && $0.closed }) else {
            throw FeasibilityGovernanceError.invalidRecord
        }
        let prior = records[index]
        records[index] = .init(taskID: prior.taskID, capability: prior.capability,
            requiredActions: prior.requiredActions, selectedPath: prior.selectedPath,
            officialEvidence: prior.officialEvidence + [newEvidence],
            accessRequirements: prior.accessRequirements, proofResult: prior.proofResult,
            state: prior.state, recordedAt: prior.recordedAt,
            context: prior.context, closed: false)
        try await store.save(records, as: fileName)
    }

    func all() async throws -> [FeasibilityCapabilityDecision] {
        try await store.load([FeasibilityCapabilityDecision].self, from: fileName) ?? []
    }
}
