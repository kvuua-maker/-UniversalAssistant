import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Canonical requirement inventory") struct RequirementInventoryTests {
    @Test func inventoryHasEveryCanonicalStableIDAndOnlyAllowedStatuses() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("REQUIREMENT_INVENTORY.json"))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let requirements = try #require(object["requirements"] as? [[String: Any]])
        #expect(object["requirement_count"] as? Int == requirements.count)
        let ids = requirements.compactMap { $0["id"] as? String }
        #expect(Set(ids).count == ids.count)
        #expect((1...1660).allSatisfy { ids.contains("MS-\($0)") })
        #expect((1...64).allSatisfy { ids.contains("MCA-\($0)") })
        #expect((1...37).allSatisfy { ids.contains("BPP-\($0)") })
        #expect((1...21).allSatisfy { ids.contains("ZOP-\($0)") })
        #expect((1...5).allSatisfy { ids.contains("DCA-\($0)") })
        let allowed = Set(["NOT_IMPLEMENTED", "IMPLEMENTED_UNVERIFIED", "VERIFIED_LOCAL",
                           "READY_FOR_LIVE_VERIFICATION", "VERIFIED_LIVE", "NOT_APPLICABLE_VERIFIED"])
        #expect(requirements.allSatisfy { allowed.contains($0["status"] as? String ?? "") })
        #expect(requirements.allSatisfy {
            $0["implementation_evidence"] is [Any] && $0["test_evidence"] is [Any] &&
            $0["commit_evidence"] is [Any] && $0["live_evidence"] is [Any]
        })
        let finalStatuses = allowed.subtracting(["NOT_IMPLEMENTED", "IMPLEMENTED_UNVERIFIED"])
        #expect(requirements.filter { finalStatuses.contains($0["status"] as? String ?? "") }.allSatisfy {
            !($0["implementation_evidence"] as? [Any] ?? []).isEmpty &&
            !($0["test_evidence"] as? [Any] ?? []).isEmpty &&
            !($0["commit_evidence"] as? [Any] ?? []).isEmpty
        })
        #expect(requirements.filter { ($0["status"] as? String) == "READY_FOR_LIVE_VERIFICATION" }.allSatisfy {
            !($0["remaining_dependency"] is NSNull) && ($0["remaining_dependency"] as? String)?.isEmpty == false
        })
    }
}
