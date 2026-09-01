import Foundation
import Testing
@testable import UniversalAssistant

private actor CalendarSpy: CalendarMutating {
    var deleted: [String] = []
    var restored: [CalendarEventSnapshot] = []
    func delete(identifier: String) { deleted.append(identifier) }
    func restore(_ snapshot: CalendarEventSnapshot) -> CalendarEventSnapshot {
        restored.append(snapshot)
        return snapshot
    }
}

struct CalendarServiceTests {
    private let start = Date(timeIntervalSince1970: 10_000)

    @Test func draftRequiresTitleAndForwardTime() {
        #expect(throws: CalendarServiceError.invalidTitle) {
            try CalendarEventDraft(title: " ", start: start, end: start.addingTimeInterval(60)).validated()
        }
        #expect(throws: CalendarServiceError.invalidDateRange) {
            try CalendarEventDraft(title: "Dentist", start: start, end: start).validated()
        }
    }

    @Test func undoCreatedEventDeletesExactIdentifier() async throws {
        let spy = CalendarSpy()
        let handler = CalendarActionUndoHandler(calendar: spy)
        try await handler.undo(.init(kind: .calendarCreate, externalIdentifier: "event-42"))
        #expect(await spy.deleted == ["event-42"])
    }

    @Test func undoUpdatedEventRestoresAuthoritativeSnapshot() async throws {
        let spy = CalendarSpy()
        let previous = CalendarEventSnapshot(
            identifier: "event-9",
            draft: .init(title: "Original", start: start, end: start.addingTimeInterval(3600))
        )
        let payload = try JSONEncoder().encode(previous)
        let handler = CalendarActionUndoHandler(calendar: spy)
        try await handler.undo(.init(kind: .calendarUpdate, externalIdentifier: "event-9", undoPayload: payload))
        #expect(await spy.restored == [previous])
    }

    @Test func unrelatedActionCannotUseCalendarUndo() async {
        let handler = CalendarActionUndoHandler(calendar: CalendarSpy())
        await #expect(throws: ActionHistoryError.nothingToUndo) {
            try await handler.undo(.init(kind: .noteCreate, externalIdentifier: "note"))
        }
    }
}
