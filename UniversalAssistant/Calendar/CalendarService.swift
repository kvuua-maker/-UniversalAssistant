import EventKit
import Foundation

enum CalendarAuthorizationState: Equatable, Sendable { case notDetermined, fullAccess, writeOnly, denied, restricted }
protocol CalendarAuthorizing: Sendable {
    func currentStatus() -> CalendarAuthorizationState
    func requestFullAccess() async throws -> Bool
}
struct SystemCalendarAuthorization: CalendarAuthorizing, @unchecked Sendable {
    private let store: EKEventStore
    init(store: EKEventStore) { self.store = store }
    func currentStatus() -> CalendarAuthorizationState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .fullAccess: .fullAccess
        case .writeOnly: .writeOnly
        case .denied: .denied
        case .restricted: .restricted
         default: .restricted
        }
    }
    func requestFullAccess() async throws -> Bool { try await store.requestFullAccessToEvents() }
}

struct CalendarEventDraft: Equatable, Codable, Sendable {
    let title: String
    let start: Date
    let end: Date
    var notes: String?

    func validated() throws -> Self {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CalendarServiceError.invalidTitle }
        guard end > start else { throw CalendarServiceError.invalidDateRange }
        return self
    }
}

struct CalendarEventSnapshot: Equatable, Codable, Sendable {
    let identifier: String
    let draft: CalendarEventDraft
}

enum CalendarServiceError: Error, Equatable {
    case permissionRequired
    case permissionDenied
    case invalidTitle
    case invalidDateRange
    case noWritableCalendar
    case eventNotFound
    case authoritativeReadBackFailed
}

protocol CalendarMutating: Sendable {
    func delete(identifier: String) async throws
    func restore(_ snapshot: CalendarEventSnapshot) async throws -> CalendarEventSnapshot
}

actor EventKitCalendarService: CalendarMutating {
    private let store: EKEventStore
    private let authorization: any CalendarAuthorizing
    init(store: EKEventStore = EKEventStore(), authorization: (any CalendarAuthorizing)? = nil) {
        self.store = store
        self.authorization = authorization ?? SystemCalendarAuthorization(store: store)
    }

    func requestFullAccessIfNeeded() async throws {
        switch authorization.currentStatus() {
        case .fullAccess: return
        case .notDetermined:
            guard try await authorization.requestFullAccess() else { throw CalendarServiceError.permissionDenied }
            for _ in 0..<20 {
                if authorization.currentStatus() == .fullAccess { return }
                try await Task.sleep(for: .milliseconds(25))
            }
            throw CalendarServiceError.permissionDenied
        case .denied, .restricted, .writeOnly: throw CalendarServiceError.permissionDenied
        }
    }

    func create(_ input: CalendarEventDraft) throws -> CalendarEventSnapshot {
        try requireFullAccess()
        let draft = try input.validated()
        guard let calendar = store.defaultCalendarForNewEvents else { throw CalendarServiceError.noWritableCalendar }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        apply(draft, to: event)
        try store.save(event, span: .thisEvent, commit: true)
        guard let identifier = event.eventIdentifier,
              let saved = store.event(withIdentifier: identifier) else { throw CalendarServiceError.authoritativeReadBackFailed }
        return snapshot(saved)
    }

    func events(from start: Date, to end: Date) throws -> [CalendarEventSnapshot] {
        try requireFullAccess()
        guard end > start else { throw CalendarServiceError.invalidDateRange }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).compactMap { event in
            guard event.eventIdentifier != nil else { return nil }
            return snapshot(event)
        }
    }

    func update(identifier: String, with input: CalendarEventDraft) throws -> CalendarEventSnapshot {
        try requireFullAccess()
        let draft = try input.validated()
        guard let event = store.event(withIdentifier: identifier) else { throw CalendarServiceError.eventNotFound }
        apply(draft, to: event)
        try store.save(event, span: .thisEvent, commit: true)
        guard let saved = store.event(withIdentifier: identifier) else { throw CalendarServiceError.authoritativeReadBackFailed }
        return snapshot(saved)
    }

    func delete(identifier: String) throws {
        try requireFullAccess()
        guard let event = store.event(withIdentifier: identifier) else { throw CalendarServiceError.eventNotFound }
        try store.remove(event, span: .thisEvent, commit: true)
        guard store.event(withIdentifier: identifier) == nil else { throw CalendarServiceError.authoritativeReadBackFailed }
    }

    func restore(_ previous: CalendarEventSnapshot) throws -> CalendarEventSnapshot {
        if store.event(withIdentifier: previous.identifier) != nil {
            return try update(identifier: previous.identifier, with: previous.draft)
        }
        return try create(previous.draft)
    }

    private func requireFullAccess() throws {
        guard authorization.currentStatus() == .fullAccess else {
            throw authorization.currentStatus() == .notDetermined ? CalendarServiceError.permissionRequired : CalendarServiceError.permissionDenied
        }
    }

    private func apply(_ draft: CalendarEventDraft, to event: EKEvent) {
        event.title = draft.title
        event.startDate = draft.start
        event.endDate = draft.end
        event.notes = draft.notes
    }

    private func snapshot(_ event: EKEvent) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            identifier: event.eventIdentifier,
            draft: .init(title: event.title ?? "", start: event.startDate, end: event.endDate, notes: event.notes)
        )
    }
}

struct CalendarActionUndoHandler: ActionUndoing {
    let calendar: any CalendarMutating

    func undo(_ record: ActionRecord) async throws {
        switch record.kind {
        case .calendarCreate:
            try await calendar.delete(identifier: record.externalIdentifier)
        case .calendarUpdate:
            let previous = try JSONDecoder().decode(CalendarEventSnapshot.self, from: record.undoPayload)
            _ = try await calendar.restore(previous)
        default:
            throw ActionHistoryError.nothingToUndo
        }
    }
}
