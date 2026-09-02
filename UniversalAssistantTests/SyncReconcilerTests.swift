import Foundation
import Testing
@testable import UniversalAssistant

private struct SyncTransportFixture: CloudSyncTransport {
    let remote: [SyncRecord]; let fails: Bool
    func fetchChanges() async throws -> [SyncRecord] { if fails { throw URLError(.notConnectedToInternet) }; return remote }
    func push(_ records: [SyncRecord]) async throws { if fails { throw URLError(.notConnectedToInternet) } }
}
private func syncRecord(_ id: String, at seconds: TimeInterval, deleted: Bool = false, device: String = "a") -> SyncRecord {
    .init(stableID: id, modifiedAt: Date(timeIntervalSince1970: seconds), payload: deleted ? nil : Data(id.utf8), isDeleted: deleted, deviceID: device)
}

@Suite("Local-primary cloud sync")
struct SyncReconcilerTests {
    @Test func conflictProducesOneDeterministicRecordWithoutDuplicateAction() {
        let result = SyncReconciler().merge(local: [syncRecord("item", at: 1)], remote: [syncRecord("item", at: 2, device: "b")])
        #expect(result.records.count == 1)
        #expect(result.records[0].modifiedAt == Date(timeIntervalSince1970: 2))
        #expect(result.conflictCount == 1)
    }

    @Test func deletionWinsAnEqualTimestampConflict() {
        let result = SyncReconciler().merge(local: [syncRecord("item", at: 2)], remote: [syncRecord("item", at: 2, deleted: true, device: "b")])
        #expect(result.records.single?.isDeleted == true)
    }

    @Test func cloudFailureReturnsLocalDataWithoutBlockingCoreUse() async {
        let local = [syncRecord("local", at: 1)]
        let outcome = await LocalPrimarySyncCoordinator(transport: SyncTransportFixture(remote: [], fails: true)).reconcile(local: local)
        #expect(outcome == .localOnly(records: local, reason: "cloud_temporarily_unavailable"))
    }
}

private extension Array { var single: Element? { count == 1 ? first : nil } }
