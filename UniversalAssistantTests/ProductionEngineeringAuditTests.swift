import Foundation
import Testing

@Suite("M11 production engineering audit")
struct ProductionEngineeringAuditTests {
    @Test func everyCanonicalProductionSurfaceHasImplementationAndEvidence() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let paths = [
            "ARCHITECTURE.md", "ROLLBACK.md", "THREAT_MODEL.md",
            "UniversalAssistant/PrivacyInfo.xcprivacy", "ADR/0005-api-versioning-webhooks.md", "OFFLINE_CAPABILITY_MATRIX.md",
            "docs/M10_LOCALIZATION_ACCESSIBILITY_QA.md", "INCIDENT_RESPONSE.md", "PERFORMANCE_BUDGET.md", "RELEASE_CHECKLIST.md",
            ".github/workflows/ci.yml", "Backend/Sources/UniversalAssistantServer/DurableJobQueue.swift",
            "Backend/Sources/UniversalAssistantServer/APNSDelivery.swift",
            "Backend/Sources/UniversalAssistantServer/ServerDataMigration.swift",
            "Backend/Sources/UniversalAssistantServer/EncryptedBackupService.swift",
            "UniversalAssistant/Persistence/AccountPolicy.swift",
            "UniversalAssistant/Persistence/LocalStore.swift"
        ]
        for path in paths {
            let url = root.appendingPathComponent(path)
            #expect(FileManager.default.fileExists(atPath: url.path), "Missing production evidence: \(path)")
            #expect((try Data(contentsOf: url)).count > 20, "Empty production evidence: \(path)")
        }
        let queue = try String(contentsOf: root.appendingPathComponent("LIVE_VERIFICATION_QUEUE.json"), encoding: .utf8)
        #expect(try JSONSerialization.jsonObject(with: Data(queue.utf8)) is [String: Any])
    }
}
