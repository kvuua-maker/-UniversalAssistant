import Foundation
import Testing

@Suite("M10 privacy compliance")
struct PrivacyComplianceTests {
    @Test func privacyManifestDeclaresNoTrackingOrCollectedDataForCurrentBuild() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("UniversalAssistant/PrivacyInfo.xcprivacy")
        let data = try Data(contentsOf: url)
        let plist = try #require(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        #expect(plist["NSPrivacyTracking"] as? Bool == false)
        #expect((plist["NSPrivacyTrackingDomains"] as? [Any])?.isEmpty == true)
        #expect((plist["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
        #expect((plist["NSPrivacyAccessedAPITypes"] as? [Any])?.isEmpty == true)
    }

    @Test func requiredPrivacyAndLegalInventoriesArePresentAndImplementationAligned() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for filename in [
            "PRIVACY_DATA_MAP.md", "DATA_PROCESSOR_INVENTORY.md", "DATA_RETENTION.md",
            "PRIVACY_POLICY.md", "TERMS_OF_USE.md", "BUSINESS_ADVERTISING_TERMS.md", "THREAT_MODEL.md"
        ] {
            let text = try String(contentsOf: root.appendingPathComponent(filename), encoding: .utf8)
            #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        let policy = try String(
            contentsOf: root.appendingPathComponent("PRIVACY_POLICY.md"), encoding: .utf8
        )
        #expect(policy.contains("diagnostic identifier"))
        #expect(policy.contains("not included in a wrong-result feedback record"))
        #expect(policy.contains("owner/legal approval"))
    }
}
