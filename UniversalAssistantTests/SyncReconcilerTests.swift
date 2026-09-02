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

    @Test func scopeSynchronizesOwnedDomainsAndExcludesDisabledOptionalStores() async {
        let values = [
            SyncRecord(stableID: "preference", kind: .preference, modifiedAt: .distantPast, payload: Data(), isDeleted: false, deviceID: "a"),
            SyncRecord(stableID: "alias", kind: .contactAlias, modifiedAt: .distantPast, payload: Data(), isDeleted: false, deviceID: "a"),
            SyncRecord(stableID: "place", kind: .savedPlace, modifiedAt: .distantPast, payload: Data(), isDeleted: false, deviceID: "a"),
            SyncRecord(stableID: "rule", kind: .proactiveRule, modifiedAt: .distantPast, payload: Data(), isDeleted: false, deviceID: "a"),
            SyncRecord(stableID: "note", kind: .assistantNote, modifiedAt: .distantPast, payload: Data(), isDeleted: false, deviceID: "a")
        ]
        let outcome = await LocalPrimarySyncCoordinator(transport: SyncTransportFixture(remote: [], fails: false)).reconcile(local: values)
        guard case let .synchronized(result) = outcome else { Issue.record("expected synchronized"); return }
        #expect(result.records.map(\.stableID) == ["alias", "place", "preference", "rule"])
    }

    @Test func cloudKitCodecRoundTripsTypedRecordAndUsesOpaqueStableRecordName() throws {
        let value = SyncRecord(stableID: "alias/user@example.com", kind: .contactAlias, modifiedAt: Date(timeIntervalSince1970: 42), payload: Data("safe".utf8), isDeleted: false, deviceID: "device-a")
        let codec = CloudKitSyncRecordCodec()
        let encoded = codec.encode(value)
        #expect(encoded.recordID.recordName != value.stableID)
        #expect(try codec.decode(encoded) == value)
    }
}

private extension Array { var single: Element? { count == 1 ? first : nil } }
