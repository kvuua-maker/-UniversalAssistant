import Foundation

struct SyncRecord: Codable, Equatable, Sendable {
    let stableID: String
    let modifiedAt: Date
    let payload: Data?
    let isDeleted: Bool
    let deviceID: String
}

struct SyncMergeResult: Equatable, Sendable {
    let records: [SyncRecord]
    let conflictCount: Int
}

struct SyncReconciler: Sendable {
    func merge(local: [SyncRecord], remote: [SyncRecord]) -> SyncMergeResult {
        var grouped: [String: [SyncRecord]] = [:]
        for record in local + remote where !record.stableID.isEmpty {
            grouped[record.stableID, default: []].append(record)
        }
        var conflicts = 0
        let records = grouped.compactMap { _, candidates -> SyncRecord? in
            if candidates.count > 1 { conflicts += 1 }
            return candidates.max { lhs, rhs in
                if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt < rhs.modifiedAt }
                if lhs.isDeleted != rhs.isDeleted { return !lhs.isDeleted && rhs.isDeleted }
                return lhs.deviceID < rhs.deviceID
            }
        }.sorted { $0.stableID < $1.stableID }
        return .init(records: records, conflictCount: conflicts)
    }
}

protocol CloudSyncTransport: Sendable {
    func fetchChanges() async throws -> [SyncRecord]
    func push(_ records: [SyncRecord]) async throws
}

enum SyncOutcome: Equatable, Sendable {
    case synchronized(SyncMergeResult)
    case localOnly(records: [SyncRecord], reason: String)
}

struct LocalPrimarySyncCoordinator: Sendable {
    let transport: any CloudSyncTransport
    func reconcile(local: [SyncRecord]) async -> SyncOutcome {
        do {
            let merged = SyncReconciler().merge(local: local, remote: try await transport.fetchChanges())
            try await transport.push(merged.records)
            return .synchronized(merged)
        } catch {
            return .localOnly(records: local, reason: "cloud_temporarily_unavailable")
        }
    }
}
