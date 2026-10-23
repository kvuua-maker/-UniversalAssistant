import Foundation

/// Protected local persistence for assistant-owned personal tasks.
///
/// System-owned records (Calendar, Reminders) stay in EventKit and are never
/// duplicated here; this store only holds items the assistant itself created
/// or observed as a consequential outcome (created event, reminder, booking
/// handoff that the user completed). Restored at launch into `My Tasks`.
actor PersonalTaskStore {
    private let store: LocalStore
    private let filename: String
    private let maximumCount: Int
    private var values: [PersonalTaskItem] = []
    private var restored = false

    init(
        store: LocalStore = .shared,
        filename: String = "personal-tasks.json",
        maximumCount: Int = 200
    ) {
        self.store = store
        self.filename = filename
        self.maximumCount = max(1, maximumCount)
    }

    func restore() async throws {
        let stored = try await store.load([PersonalTaskItem].self, from: filename) ?? []
        values = Array(stored.filter(Self.valid).prefix(maximumCount))
        restored = true
    }

    func upsert(_ item: PersonalTaskItem) async throws {
        guard Self.valid(item) else { throw PersonalTaskStoreError.invalidTask }
        values.removeAll { $0.id == item.id }
        values.insert(item, at: 0)
        let live = values.filter { ![.completed, .cancelled].contains($0.status) }
        values = Array(live.prefix(maximumCount))
        try await store.save(values, as: filename)
    }

    func remove(id: String) async throws {
        values.removeAll { $0.id == id }
        try await store.save(values, as: filename)
    }

    func snapshot() async -> [PersonalTaskItem] {
        if !restored {
            try? await restore()
        }
        return values
    }

    private static func valid(_ item: PersonalTaskItem) -> Bool {
        !item.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !item.externalReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && item.title.count <= 160
    }
}

enum PersonalTaskStoreError: Error, Equatable { case invalidTask }
