@preconcurrency import CloudKit
import CryptoKit
import Foundation

enum CloudKitSyncError: Error, Equatable {
    case accountUnavailable
    case malformedRecord
    case partialFailure
}

struct CloudKitSyncRecordCodec: Sendable {
    static let recordType = "AssistantOwnedRecord"

    func recordID(for stableID: String) -> CKRecord.ID {
        let digest = SHA256.hash(data: Data(stableID.utf8)).map { String(format: "%02x", $0) }.joined()
        return CKRecord.ID(recordName: digest)
    }

    func encode(_ value: SyncRecord) -> CKRecord {
        let record = CKRecord(recordType: Self.recordType, recordID: recordID(for: value.stableID))
        record["stableID"] = value.stableID as NSString
        record["kind"] = value.kind.rawValue as NSString
        record["modifiedAt"] = value.modifiedAt as NSDate
        record["isDeleted"] = NSNumber(value: value.isDeleted)
        record["deviceID"] = value.deviceID as NSString
        if let payload = value.payload { record["payload"] = payload as NSData }
        return record
    }

    func decode(_ record: CKRecord) throws -> SyncRecord {
        guard
            let stableID = record["stableID"] as? String,
            !stableID.isEmpty,
            let kindRaw = record["kind"] as? String,
            let kind = SyncRecordKind(rawValue: kindRaw),
            let modifiedAt = record["modifiedAt"] as? Date,
            let isDeleted = record["isDeleted"] as? NSNumber,
            let deviceID = record["deviceID"] as? String,
            !deviceID.isEmpty
        else { throw CloudKitSyncError.malformedRecord }
        let payload = record["payload"] as? Data
        guard isDeleted.boolValue || payload != nil else { throw CloudKitSyncError.malformedRecord }
        return SyncRecord(stableID: stableID, kind: kind, modifiedAt: modifiedAt, payload: payload, isDeleted: isDeleted.boolValue, deviceID: deviceID)
    }
}

actor CloudKitSyncTransport: CloudSyncTransport {
    private let container: CKContainer
    private let database: CKDatabase
    private let codec = CloudKitSyncRecordCodec()

    init(container: CKContainer = .default()) {
        self.container = container
        self.database = container.privateCloudDatabase
    }

    func fetchChanges() async throws -> [SyncRecord] {
        guard try await container.accountStatus() == .available else { throw CloudKitSyncError.accountUnavailable }
        var cursor: CKQueryOperation.Cursor?
        var output: [SyncRecord] = []
        repeat {
            let keys = ["stableID", "kind", "modifiedAt", "isDeleted", "deviceID", "payload"]
            let page: (matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)], queryCursor: CKQueryOperation.Cursor?)
            if let cursor {
                page = try await database.records(continuingMatchFrom: cursor, desiredKeys: keys, resultsLimit: 200)
            } else {
                page = try await database.records(
                    matching: CKQuery(recordType: CloudKitSyncRecordCodec.recordType, predicate: NSPredicate(value: true)),
                    desiredKeys: keys,
                    resultsLimit: 200
                )
            }
            for (_, result) in page.matchResults {
                guard case let .success(record) = result else { throw CloudKitSyncError.partialFailure }
                output.append(try codec.decode(record))
            }
            cursor = page.queryCursor
        } while cursor != nil
        return output.sorted { $0.stableID < $1.stableID }
    }

    func push(_ records: [SyncRecord]) async throws {
        guard try await container.accountStatus() == .available else { throw CloudKitSyncError.accountUnavailable }
        for record in records { _ = try await database.save(codec.encode(record)) }
    }
}
