import Foundation

enum AssistantActionKind: String, Codable, Sendable {
    case calendarCreate, calendarUpdate, reminderCreate, noteCreate, linkedPlan
}

enum ActionRecordStatus: String, Codable, Sendable {
    case completed, undoing, undone
}

struct ActionRecord: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let kind: AssistantActionKind
    let externalIdentifier: String
    let createdAt: Date
    let undoPayload: Data
    var status: ActionRecordStatus

    init(
        id: UUID = UUID(),
        kind: AssistantActionKind,
        externalIdentifier: String,
        createdAt: Date = .now,
        undoPayload: Data = Data(),
        status: ActionRecordStatus = .completed
    ) {
        self.id = id
        self.kind = kind
        self.externalIdentifier = externalIdentifier
        self.createdAt = createdAt
        self.undoPayload = undoPayload
        self.status = status
    }
}

protocol ActionHistoryPersisting: Sendable {
    func load() async throws -> [ActionRecord]
    func save(_ records: [ActionRecord]) async throws
}

actor LocalActionHistoryPersistence: ActionHistoryPersisting {
    private let store: LocalStore
    private let filename: String

    init(store: LocalStore = .shared, filename: String = "action-history.json") {
        self.store = store
        self.filename = filename
    }

    func load() async throws -> [ActionRecord] {
        try await store.load([ActionRecord].self, from: filename) ?? []
    }

    func save(_ records: [ActionRecord]) async throws {
        try await store.save(records, as: filename)
    }
}

protocol ActionUndoing: Sendable {
    func undo(_ record: ActionRecord) async throws
}

enum ActionHistoryError: Error, Equatable {
    case nothingToUndo
}

actor ActionHistory {
    private let persistence: any ActionHistoryPersisting
    private let capacity: Int
    private var records: [ActionRecord] = []

    init(persistence: any ActionHistoryPersisting = LocalActionHistoryPersistence(), capacity: Int = 100) {
        self.persistence = persistence
        self.capacity = max(1, capacity)
    }

    func restore() async throws {
        records = try await persistence.load()
            .map { record in
                var recovered = record
                if recovered.status == .undoing { recovered.status = .completed }
                return recovered
            }
            .sorted { $0.createdAt < $1.createdAt }
            .suffix(capacity)
            .map(\.self)
    }

    func record(_ record: ActionRecord) async throws {
        guard !record.externalIdentifier.isEmpty else { return }
        records.append(record)
        if records.count > capacity { records.removeFirst(records.count - capacity) }
        try await persistence.save(records)
    }

    func latestUndoable() -> ActionRecord? {
        records.last { $0.status == .completed }
    }

    @discardableResult
    func undoLast(using handler: any ActionUndoing) async throws -> ActionRecord {
        guard let index = records.lastIndex(where: { $0.status == .completed }) else {
            throw ActionHistoryError.nothingToUndo
        }
        records[index].status = .undoing
        try await persistence.save(records)
        let pending = records[index]
        do {
            try await handler.undo(pending)
            records[index].status = .undone
            try await persistence.save(records)
            return records[index]
        } catch {
            records[index].status = .completed
            try? await persistence.save(records)
            throw error
        }
    }

    func snapshot() -> [ActionRecord] { records }
}
