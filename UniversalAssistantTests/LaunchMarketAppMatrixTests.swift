import Testing
@testable import UniversalAssistant

@Suite("Launch-market app capability matrix") struct LaunchMarketAppMatrixTests {
    @Test func everyEntryPassesRegistryEvidenceValidation() async throws {
        let registry = try AppCapabilityRegistry(records: LaunchMarketAppMatrix.records)
        #expect(await registry.eligible(region: "UA", capability: .navigate).map(\.id) == ["google-maps", "waze"])
    }
    @Test func messagingNeverClaimsSilentSend() {
        for id in ["telegram", "viber"] {
            let record = LaunchMarketAppMatrix.records.first { $0.id == id }
            #expect(record?.capabilities.contains(.send) == true)
            #expect(record?.limitations.contains { $0.lowercased().contains("user") } == true)
        }
    }
    @Test func appleMusicRemainsAuthorizationAndDeviceGated() {
        let record = LaunchMarketAppMatrix.records.first { $0.id == "apple-music" }
        #expect(record?.authenticationRequired == true)
        #expect(record?.testStatus == .deviceTestRequired)
    }
}
