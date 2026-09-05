import Foundation
import Testing
@testable import UniversalAssistant

private struct EventKitExecutorStub: EventKitCommandExecuting {
    let result: Result<EventKitExecutionResult, Error>
    func execute(_ command: StructuredCommand) async throws -> EventKitExecutionResult { try result.get() }
}

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

    @Test(arguments: [("Додай зустріч Team Sync завтра о 09:30", CommandLanguage.uk), ("Создай встречу Team Sync завтра в 09:30", .ru), ("Add event Team Sync tomorrow at 9:30 am", .en), ("Termin erstellen Team Sync morgen um 09:30", .de), ("Ajoute un rendez-vous Team Sync demain à 09:30", .fr)])
    func semanticVariantsProduceSameTypedArguments(text: String, language: CommandLanguage) {
        let command = StructuredCommand(originalText: text, normalizedText: text.lowercased(), language: language, intent: .calendarCreate, risk: .reversible)
        let value = EventKitCommandArgumentExtractor().extract(command, now: start, timeZone: TimeZone(identifier: "Europe/Kyiv")!)
        #expect(value.subject?.localizedCaseInsensitiveContains("Team Sync") == true)
        #expect(value.dateTime?.precision == .minute)
    }

    @Test @MainActor func viewModelExecutesEventKitContract() async throws {
        let expected = EventKitExecutionResult(kind: .calendar, operation: .created, title: "Team Sync", detail: "Tomorrow", itemCount: 1)
        let model = AssistantViewModel(eventKitExecutor: EventKitExecutorStub(result: .success(expected)))
        model.input = "Додай зустріч Team Sync завтра о 09:30"
        model.submit()
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.resultState == .eventKit(expected))
    }

    @Test @MainActor func deletePreservesConfirmationGate() {
        let expected = EventKitExecutionResult(kind: .calendar, operation: .deleted, title: "Team Sync", detail: "Deleted", itemCount: 1)
        let model = AssistantViewModel(eventKitExecutor: EventKitExecutorStub(result: .success(expected)))
        model.input = "Видали зустріч Team Sync"
        model.submit()
        guard case .actionRequired = model.resultState else { Issue.record("Expected confirmation"); return }
    }
}
