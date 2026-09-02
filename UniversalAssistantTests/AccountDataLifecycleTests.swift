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

    @Test func userCanViewEditDeleteClearAndExportDurableOwnedRecords() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let dataStore = AssistantOwnedDataStore(store: LocalStore(baseDirectory: directory), fileName: "owned.json")
        let first = SyncRecord(stableID: "place-home", kind: .savedPlace, modifiedAt: .distantPast, payload: Data("home".utf8), isDeleted: false, deviceID: "device")
        try await dataStore.upsert(first)
        #expect(try await dataStore.records() == [first])

        let edited = SyncRecord(stableID: first.stableID, kind: first.kind, modifiedAt: Date(timeIntervalSince1970: 1), payload: Data("new-home".utf8), isDeleted: false, deviceID: "device")
        try await dataStore.upsert(edited)
        #expect(try await dataStore.records() == [edited])
        #expect(String(decoding: try await dataStore.export(at: .distantPast), as: UTF8.self).contains("place-home"))

        try await dataStore.delete(stableID: first.stableID, at: Date(timeIntervalSince1970: 2), deviceID: "device")
        let deleted = try await dataStore.records()
        #expect(deleted.count == 1 && deleted.first?.isDeleted == true)
        try await dataStore.clear(at: Date(timeIntervalSince1970: 3), deviceID: "device")
        let cleared = try await dataStore.records()
        #expect(cleared.count == 1 && cleared.first?.isDeleted == true)
    }
}
