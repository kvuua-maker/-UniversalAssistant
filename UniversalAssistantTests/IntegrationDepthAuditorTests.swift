import Testing
@testable import UniversalAssistant

@Suite("Integration depth audit")
struct IntegrationDepthAuditorTests {
    @Test func launchMarketRecordsNeverBecomeProductionVerifiedFromDocumentation() {
        let findings = LaunchMarketAppMatrix.records.map(IntegrationDepthAuditor().audit)
        #expect(findings.allSatisfy { !$0.productionVerified })
    }

    @Test func handoffDoesNotBecomeReadOrWriteDepth() throws {
        let telegram = try #require(LaunchMarketAppMatrix.records.first { $0.id == "telegram" })
        #expect(IntegrationDepthAuditor().audit(telegram).maximumClaimableDepth == .contextHandoff)
        #expect(!IntegrationDepthAuditor().audit(telegram).productionVerified)
    }

    @Test func mapsExactContextRemainsContextHandoff() throws {
        let maps = try #require(LaunchMarketAppMatrix.records.first { $0.id == "google-maps" })
        #expect(IntegrationDepthAuditor().audit(maps).maximumClaimableDepth == .contextHandoff)
    }
}
