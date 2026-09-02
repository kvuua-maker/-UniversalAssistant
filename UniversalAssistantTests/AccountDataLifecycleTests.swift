import Foundation
import Testing
@testable import UniversalAssistant

private struct CleanupFixture: AccountCleanupOperation {
    let kind: AccountCleanupKind; let fails: Bool
    func execute() async throws { if fails { throw URLError(.cannotConnectToHost) } }
}

@Suite("Account deletion and export")
struct AccountDataLifecycleTests {
    @Test func deletionReportsEveryIndependentCleanupTruthfully() async {
        let report = await AccountDeletionCoordinator().delete(using: [
            CleanupFixture(kind: .pushTokens, fails: false), CleanupFixture(kind: .proactiveJobs, fails: true),
            CleanupFixture(kind: .providerConnections, fails: false), CleanupFixture(kind: .cloudData, fails: false),
            CleanupFixture(kind: .localAccountSession, fails: false)
        ])
        #expect(report.results.count == AccountCleanupKind.allCases.count)
        #expect(!report.isComplete)
        #expect(report.results.contains { $0.kind == .proactiveJobs && $0.status == .failed(reason: "cleanup_failed") })
    }

    @Test func duplicateCleanupKindExecutesOnlyOneContract() async {
        let report = await AccountDeletionCoordinator().delete(using: [CleanupFixture(kind: .pushTokens, fails: false), CleanupFixture(kind: .pushTokens, fails: false)])
        #expect(report.results.count == 1)
    }

    @Test func exportIsPortableSortedJSONOfAssistantOwnedRecords() throws {
        let record = SyncRecord(stableID: "alias-1", modifiedAt: .distantPast, payload: Data("value".utf8), isDeleted: false, deviceID: "device")
        let data = try AssistantOwnedDataExport(exportedAt: .distantPast, schemaVersion: 1, records: [record]).json()
        #expect(String(decoding: data, as: UTF8.self).contains("alias-1"))
    }
}
