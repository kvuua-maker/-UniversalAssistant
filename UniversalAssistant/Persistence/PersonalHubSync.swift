import Foundation

/// Local-first replication for assistant-owned favorites.
///
/// The canonical rule (ADR 0003) is local-primary sync: an outage must never
/// block local use. CloudKit is therefore only selected when the build actually
/// carries the entitlement behind `UAUseCloudKitSync`; otherwise records are
/// mirrored into protected local storage through the same `CloudSyncTransport`
/// contract, so the pipeline is exercised and testable on any build.
struct LocalMirrorTransport: CloudSyncTransport {
    private let store: LocalStore
    private let filename: String

    init(store: LocalStore = .shared, filename: String = "sync-mirror.json") {
        self.store = store
        self.filename = filename
    }

    func fetchChanges() async throws -> [SyncRecord] {
        try await store.load([SyncRecord].self, from: filename) ?? []
    }

    func push(_ records: [SyncRecord]) async throws {
        try await store.save(records, as: filename)
    }
}

enum SyncTransportFactory {
    static var usesCloudKit: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "UAUseCloudKitSync") as? Bool) ?? false
    }

    static func make() -> any CloudSyncTransport {
        usesCloudKit ? CloudKitSyncTransport() : LocalMirrorTransport()
    }
}

/// Maps `FavoriteReference` values onto the sync record contract without
/// leaking the domain model into the transport.
struct PersonalHubSync {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func records(from favorites: [FavoriteReference], deviceID: String) -> [SyncRecord] {
        favorites.compactMap { favorite in
            guard let payload = try? encoder.encode(favorite) else { return nil }
            return SyncRecord(
                stableID: favorite.id,
                kind: .savedPlace,
                modifiedAt: favorite.sourceUpdatedAt ?? favorite.lastRefreshAttemptAt ?? Date(),
                payload: payload,
                isDeleted: false,
                deviceID: deviceID)
        }
    }

    func favorites(from records: [SyncRecord]) -> [FavoriteReference] {
        records.compactMap { record in
            guard record.kind == .savedPlace, !record.isDeleted, let payload = record.payload else {
                return nil
            }
            return try? decoder.decode(FavoriteReference.self, from: payload)
        }
    }
}
