import Foundation

enum SyncRecordKind: String, Codable, CaseIterable, Sendable {
    case preference
    case contactAlias
    case savedPlace
    case proactiveRule
    case assistantNote
    case assistantShoppingList
}

struct SyncRecord: Codable, Equatable, Sendable {
    let stableID: String
    let kind: SyncRecordKind
    let modifiedAt: Date
    let payload: Data?
    let isDeleted: Bool
    let deviceID: String

    init(stableID: String, kind: SyncRecordKind = .preference, modifiedAt: Date, payload: Data?, isDeleted: Bool, deviceID: String) {
        self.stableID = stableID
        self.kind = kind
        self.modifiedAt = modifiedAt
        self.payload = payload
        self.isDeleted = isDeleted
        self.deviceID = deviceID
    }
}

struct AssistantOwnedSyncScope: Sendable {
    let optionalNotesEnabled: Bool
    let optionalShoppingListsEnabled: Bool

    func permits(_ kind: SyncRecordKind) -> Bool {
        switch kind {
        case .preference, .contactAlias, .savedPlace, .proactiveRule: true
        case .assistantNote: optionalNotesEnabled
        case .assistantShoppingList: optionalShoppingListsEnabled
        }
    }
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
    var scope = AssistantOwnedSyncScope(optionalNotesEnabled: false, optionalShoppingListsEnabled: false)
    func reconcile(local: [SyncRecord]) async -> SyncOutcome {
        let permitted = local.filter { scope.permits($0.kind) }
        do {
            let remote = try await transport.fetchChanges().filter { scope.permits($0.kind) }
            let merged = SyncReconciler().merge(local: permitted, remote: remote)
            try await transport.push(merged.records)
            return .synchronized(merged)
        } catch {
            return .localOnly(records: permitted, reason: "cloud_temporarily_unavailable")
        }
    }
}
