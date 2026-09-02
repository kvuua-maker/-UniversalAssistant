import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Execution state governance") struct ExecutionStateGovernanceTests {
    private var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent() }

    @Test func repositoryStateArtifactsAreMachineValidAndComplete() throws {
        let heartbeat = try JSONDecoder().decode(DevelopmentHeartbeat.self, from: Data(contentsOf: root.appendingPathComponent("PROGRESS_HEARTBEAT.json")))
        #expect(!heartbeat.currentBlock.isEmpty); #expect(!heartbeat.currentAction.isEmpty); #expect(!heartbeat.attemptPathID.isEmpty); #expect(!heartbeat.lastCommit.isEmpty)
        let status = try String(contentsOf: root.appendingPathComponent("PROJECT_STATUS.md"), encoding: .utf8)
        for field in ["Current block/action:", "Last measurable progress:", "Last successful build/test:", "Last commit:", "External blocker:", "Internal engineering problems:", "STALLED:", "Next block:", "OWNER ACTION REQUIRED:"] { #expect(status.contains(field)) }
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("ATTEMPT_LEDGER.json"))) as? [String: Any]
        let attempts = object?["attempts"] as? [[String: Any]] ?? []
        let fields = Set(["id", "problem", "method_path_signature", "material_inputs_configuration", "error_signature", "evidence", "diagnosis", "documentation_checked", "conclusion", "next_hypothesis", "result"])
        #expect(!attempts.isEmpty); #expect(attempts.allSatisfy { fields.isSubset(of: Set($0.keys)) })
    }

    @Test func watchdogFlagsStaleWorkAndExemptsHealthyLongRunningWork() {
        func data(_ status: String) -> Data {
            try! JSONSerialization.data(withJSONObject: ["current_block":"M12", "current_action":"state audit", "status":status, "last_measurable_progress":"2026-09-02T10:00:00Z", "attempt_path_id":"audit-v1", "last_commit":"abc", "blocker":NSNull()])
        }
        let dashboard = "Current block/action: state audit\nSTALLED: NO"
        let now = ISO8601DateFormatter().date(from: "2026-09-02T11:00:00Z")!
        let old = ISO8601DateFormatter().date(from: "2026-09-02T10:00:00Z")!
        #expect(DevelopmentStateWatchdog().inspect(heartbeatData: data("IN_PROGRESS"), projectStatus: dashboard, now: now) == .stale(lastProgress: old, action: "state audit"))
        #expect(DevelopmentStateWatchdog().inspect(heartbeatData: data("LONG_RUNNING"), projectStatus: dashboard, now: now) == .healthy)
    }

    @Test func watchdogNeverConvertsMalformedStateIntoSuccess() {
        #expect(DevelopmentStateWatchdog().inspect(heartbeatData: Data("{}".utf8), projectStatus: "STALLED: NO", now: .now) == .malformedHeartbeat)
    }
}
