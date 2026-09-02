import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Feasibility path governance") struct FeasibilityPathGovernanceTests {
    private func decision(capability: String = "SEARCH", path: String = "official API", closed: Bool = true, state: FeasibilityGateState = .passSelectedPath) -> FeasibilityCapabilityDecision {
        .init(taskID: "gmail-search", capability: capability, requiredActions: [capability],
              selectedPath: path, officialEvidence: ["official-doc:2026-09-02"],
              accessRequirements: ["OAuth"], proofResult: "E1 contract plus E3 adapter",
              state: state, recordedAt: Date(timeIntervalSince1970: 1),
              context: "M12 feasibility audit", closed: closed)
    }

    @Test func passIsPerExactCapabilityAndPersists() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = LocalStore(baseDirectory: directory)
        let registry = FeasibilityPathRegistry(store: store)
        try await registry.record(decision())
        try await registry.record(.init(taskID: "gmail-send", capability: "SEND", requiredActions: ["SEND"], selectedPath: "official API", officialEvidence: ["official-doc:2026-09-02"], accessRequirements: ["OAuth send scope"], proofResult: "live proof needs account", state: .needsOwnerAccessForProof, recordedAt: Date(timeIntervalSince1970: 2), context: "M12 feasibility audit", closed: false))
        #expect(try await FeasibilityPathRegistry(store: store).all().map(\.capability) == ["SEARCH", "SEND"])
    }

    @Test func closedPassCannotBeDuplicatedOrReopenedWithoutEvidence() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let registry = FeasibilityPathRegistry(store: LocalStore(baseDirectory: directory))
        try await registry.record(decision())
        await #expect(throws: FeasibilityGovernanceError.duplicateCapability) { try await registry.record(self.decision(path: "different SDK")) }
        await #expect(throws: FeasibilityGovernanceError.reopenWithoutNewEvidence) { try await registry.reopen(taskID: "gmail-search", capability: "SEARCH", newEvidence: " ") }
        try await registry.reopen(taskID: "gmail-search", capability: "SEARCH", newEvidence: "provider API version changed")
        #expect(try await registry.all().first?.closed == false)
    }

    @Test func onlyPassingPathCanCloseAndOneTaskHasOneActivePath() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let registry = FeasibilityPathRegistry(store: LocalStore(baseDirectory: directory))
        await #expect(throws: FeasibilityGovernanceError.closedWithoutPassingPath) { try await registry.record(self.decision(closed: true, state: .unsupported)) }
        try await registry.record(decision(closed: false, state: .externalBlocked))
        await #expect(throws: FeasibilityGovernanceError.secondActivePath) { try await registry.record(self.decision(capability: "READ", closed: false, state: .externalBlocked)) }
    }
}
