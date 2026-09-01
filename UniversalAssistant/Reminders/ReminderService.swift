@preconcurrency import EventKit
import Foundation

struct ReminderDraft: Equatable, Codable, Sendable {
    let title: String
    var dueDate: Date?
    var notes: String?
    var priority: Int = 0

    func validated() throws -> Self {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReminderServiceError.invalidTitle
        }
        guard (0...9).contains(priority) else { throw ReminderServiceError.invalidPriority }
        return self
    }
}

struct ReminderSnapshot: Equatable, Codable, Sendable {
    let identifier: String
    let draft: ReminderDraft
    let isCompleted: Bool
}

enum ReminderServiceError: Error, Equatable {
    case permissionRequired
    case permissionDenied
    case invalidTitle
    case invalidPriority
    case noWritableList
    case reminderNotFound
    case authoritativeReadBackFailed
}

protocol ReminderMutating: Sendable {
    func delete(identifier: String) async throws
    func restore(_ snapshot: ReminderSnapshot) async throws -> ReminderSnapshot
}

actor EventKitReminderService: ReminderMutating {
    private let store = EKEventStore()

    func requestFullAccessIfNeeded() async throws {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: return
        case .notDetermined:
            guard try await store.requestFullAccessToReminders() else { throw ReminderServiceError.permissionDenied }
        case .denied, .restricted, .writeOnly: throw ReminderServiceError.permissionDenied
        @unknown default: throw ReminderServiceError.permissionDenied
        }
    }

    func create(_ input: ReminderDraft) throws -> ReminderSnapshot {
        try requireFullAccess()
        let draft = try input.validated()
        guard let calendar = store.defaultCalendarForNewReminders() else { throw ReminderServiceError.noWritableList }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = calendar
        apply(draft, to: reminder)
        try store.save(reminder, commit: true)
        let identifier = reminder.calendarItemIdentifier
        guard let saved = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw ReminderServiceError.authoritativeReadBackFailed
        }
        return snapshot(saved)
    }

    func incomplete(dueFrom start: Date?, to end: Date?) async throws -> [ReminderSnapshot] {
        try requireFullAccess()
        if let start, let end, end <= start { throw CalendarServiceError.invalidDateRange }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: start, ending: end, calendars: nil)
        return try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let values = (reminders ?? []).map(Self.snapshotValue)
                continuation.resume(returning: values)
            }
        }
    }

    func update(identifier: String, with input: ReminderDraft, isCompleted: Bool? = nil) throws -> ReminderSnapshot {
        try requireFullAccess()
        let draft = try input.validated()
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw ReminderServiceError.reminderNotFound
        }
        apply(draft, to: reminder)
        if let isCompleted { reminder.isCompleted = isCompleted }
        try store.save(reminder, commit: true)
        guard let saved = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw ReminderServiceError.authoritativeReadBackFailed
        }
        return snapshot(saved)
    }

    func delete(identifier: String) throws {
        try requireFullAccess()
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw ReminderServiceError.reminderNotFound
        }
        try store.remove(reminder, commit: true)
        guard store.calendarItem(withIdentifier: identifier) == nil else {
            throw ReminderServiceError.authoritativeReadBackFailed
        }
    }

    func restore(_ previous: ReminderSnapshot) throws -> ReminderSnapshot {
        if store.calendarItem(withIdentifier: previous.identifier) != nil {
            return try update(identifier: previous.identifier, with: previous.draft, isCompleted: previous.isCompleted)
        }
        return try create(previous.draft)
    }

    private func requireFullAccess() throws {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            throw EKEventStore.authorizationStatus(for: .reminder) == .notDetermined
                ? ReminderServiceError.permissionRequired : ReminderServiceError.permissionDenied
        }
    }

    private func apply(_ draft: ReminderDraft, to reminder: EKReminder) {
        reminder.title = draft.title
        reminder.notes = draft.notes
        reminder.priority = draft.priority
        reminder.dueDateComponents = draft.dueDate.map { Calendar.current.dateComponents(in: .current, from: $0) }
    }

    private func snapshot(_ reminder: EKReminder) -> ReminderSnapshot { Self.snapshotValue(reminder) }

    nonisolated private static func snapshotValue(_ reminder: EKReminder) -> ReminderSnapshot {
        ReminderSnapshot(
            identifier: reminder.calendarItemIdentifier,
            draft: .init(
                title: reminder.title,
                dueDate: reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
                notes: reminder.notes,
                priority: reminder.priority
            ),
            isCompleted: reminder.isCompleted
        )
    }
}

struct ReminderActionUndoHandler: ActionUndoing {
    let reminders: any ReminderMutating

    func undo(_ record: ActionRecord) async throws {
        switch record.kind {
        case .reminderCreate:
            try await reminders.delete(identifier: record.externalIdentifier)
        case .reminderUpdate:
            let previous = try JSONDecoder().decode(ReminderSnapshot.self, from: record.undoPayload)
            _ = try await reminders.restore(previous)
        default:
            throw ActionHistoryError.nothingToUndo
        }
    }
}
