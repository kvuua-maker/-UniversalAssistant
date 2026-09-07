import Foundation
import Testing
@testable import UniversalAssistant

private actor DirectCalendarStub: EventKitCalendarExecuting {
    var items: [CalendarEventSnapshot] = []
    func seed(_ value: CalendarEventSnapshot) { items.append(value) }
    func requestFullAccessIfNeeded() {}
    func create(_ input: CalendarEventDraft) -> CalendarEventSnapshot { let value = CalendarEventSnapshot(identifier: "calendar-new", draft: input); items.append(value); return value }
    func events(from: Date, to: Date) -> [CalendarEventSnapshot] { items }
    func update(identifier: String, with input: CalendarEventDraft) throws -> CalendarEventSnapshot { guard let i = items.firstIndex(where: { $0.identifier == identifier }) else { throw CalendarServiceError.eventNotFound }; let value = CalendarEventSnapshot(identifier: identifier, draft: input); items[i] = value; return value }
    func delete(identifier: String) throws { guard let i = items.firstIndex(where: { $0.identifier == identifier }) else { throw CalendarServiceError.eventNotFound }; items.remove(at: i) }
    func restore(_ snapshot: CalendarEventSnapshot) -> CalendarEventSnapshot { items.removeAll { $0.identifier == snapshot.identifier }; items.append(snapshot); return snapshot }
}

private actor DirectReminderStub: EventKitReminderExecuting {
    var items: [ReminderSnapshot]
    init(_ items: [ReminderSnapshot] = []) { self.items = items }
    func seed(_ value: ReminderSnapshot) { items.append(value) }
    func requestFullAccessIfNeeded() {}
    func create(_ input: ReminderDraft) -> ReminderSnapshot { let value = ReminderSnapshot(identifier: "reminder-new", draft: input, isCompleted: false); items.append(value); return value }
    func incomplete(dueFrom: Date?, to: Date?) -> [ReminderSnapshot] { items.filter { !$0.isCompleted } }
    func update(identifier: String, with input: ReminderDraft, isCompleted: Bool?) throws -> ReminderSnapshot { guard let i = items.firstIndex(where: { $0.identifier == identifier }) else { throw ReminderServiceError.reminderNotFound }; let value = ReminderSnapshot(identifier: identifier, draft: input, isCompleted: isCompleted ?? items[i].isCompleted); items[i] = value; return value }
    func delete(identifier: String) throws { guard let i = items.firstIndex(where: { $0.identifier == identifier }) else { throw ReminderServiceError.reminderNotFound }; items.remove(at: i) }
    func restore(_ snapshot: ReminderSnapshot) -> ReminderSnapshot { items.removeAll { $0.identifier == snapshot.identifier }; items.append(snapshot); return snapshot }
}

private actor DirectMemoryHistoryStore: ActionHistoryPersisting {
    var records: [ActionRecord] = []
    func load() -> [ActionRecord] { records }
    func save(_ records: [ActionRecord]) { self.records = records }
}

private actor FailingHistoryStore: ActionHistoryPersisting {
    func load() -> [ActionRecord] { [] }
    func save(_ records: [ActionRecord]) throws { throw CocoaError(.fileWriteUnknown) }
}

struct EventKitCommandExecutorDirectTests {
    private func command(_ text: String, intent: CommandIntent, entities: [String:String] = [:]) -> StructuredCommand { .init(originalText: text, normalizedText: text.lowercased(), language: .uk, intent: intent, entities: entities, risk: .reversible) }

    @Test func shoppingAddRequiresAuthoritativeListAndRecordsHistory() async throws {
        let reminders = DirectReminderStub(); let history = ActionHistory(persistence: DirectMemoryHistoryStore())
        let executor = ProductionEventKitCommandExecutor(calendar: DirectCalendarStub(), reminders: reminders, history: history)
        await #expect(throws: EventKitExecutionError.missingSubject) { try await executor.execute(command("Додай молоко до списку покупок", intent: .shoppingList)) }
        let result = try await executor.execute(command("Додай молоко до списку покупок", intent: .shoppingList, entities: ["selected_list_id":"list-1"]))
        #expect(result.operation == .created); #expect((await reminders.items).first?.draft.listIdentifier == "list-1"); #expect(await history.latestUndoable()?.kind == .reminderCreate)
    }

    @Test func shoppingDeleteUsesExactSelectedItemAndUnresolvedFailsClosed() async throws {
        let draft = ReminderDraft(title: "Milk", dueDate: nil, notes: nil, priority: 0, timeZoneIdentifier: nil, locationTrigger: nil, listIdentifier: "list-1")
        let reminders = DirectReminderStub([.init(identifier: "r1", draft: draft, isCompleted: false), .init(identifier: "r2", draft: draft, isCompleted: false)])
        let executor = ProductionEventKitCommandExecutor(calendar: DirectCalendarStub(), reminders: reminders, history: ActionHistory(persistence: DirectMemoryHistoryStore()))
        await #expect(throws: EventKitExecutionError.missingSubject) { try await executor.execute(command("Видали молоко зі списку покупок", intent: .shoppingList)) }
        let result = try await executor.execute(command("Видали молоко зі списку покупок", intent: .shoppingList, entities: ["selected_item_id":"r2"]))
        #expect(result.operation == .deleted); #expect(await reminders.items.map(\.identifier) == ["r1"])
    }

    @Test func eventKitSuccessSurvivesHistoryPersistenceFailure() async throws {
        let history = ActionHistory(persistence: FailingHistoryStore())
        let executor = ProductionEventKitCommandExecutor(calendar: DirectCalendarStub(), reminders: DirectReminderStub(), history: history)
        let result = try await executor.execute(command("Додай молоко до списку покупок", intent: .shoppingList, entities: ["selected_list_id":"list-1"]))
        #expect(result.operation == .created)
    }

    @Test func productionUndoReportsTruthfulUndoneOperation() async throws {
        let reminders = DirectReminderStub(); let history = ActionHistory(persistence: DirectMemoryHistoryStore())
        let executor = ProductionEventKitCommandExecutor(calendar: DirectCalendarStub(), reminders: reminders, history: history)
        _ = try await executor.execute(command("Додай молоко до списку покупок", intent: .shoppingList, entities: ["selected_list_id":"list-1"]))
        let result = try await executor.execute(command("Відміни останнє", intent: .undo))
        #expect(result.operation == .undone); #expect(await reminders.items.isEmpty)
    }
}

extension EventKitCommandExecutorDirectTests {
    @Test func calendarCreateUpdateDeleteRecordAndUndoAuthoritativeHistory() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let calendar = DirectCalendarStub(); let history = ActionHistory(persistence: DirectMemoryHistoryStore())
        let executor = ProductionEventKitCommandExecutor(calendar: calendar, reminders: DirectReminderStub(), history: history, now: { start }, timeZone: TimeZone(identifier: "Europe/Kyiv")!)
        let created = try await executor.execute(command("Додай зустріч Team Sync завтра о 09:30", intent: .calendarCreate))
        #expect(created.operation == .created); #expect(await history.latestUndoable()?.kind == .calendarCreate)
        #expect(try await executor.execute(command("Відміни останнє", intent: .undo)).operation == .undone)
        let original = CalendarEventSnapshot(identifier: "event-1", draft: .init(title: "Dentist", start: start.addingTimeInterval(3600), end: start.addingTimeInterval(7200)))
        await calendar.seed(original)
        let updated = try await executor.execute(command("Перенеси зустріч Dentist завтра о 10:00", intent: .calendarUpdate))
        #expect(updated.operation == .updated); #expect(await history.latestUndoable()?.kind == .calendarUpdate); #expect((await history.latestUndoable()?.undoPayload.isEmpty) == false)
        #expect(try await executor.execute(command("Відміни останнє", intent: .undo)).operation == .undone)
        let deleted = try await executor.execute(command("Видали зустріч Dentist", intent: .calendarDelete))
        #expect(deleted.operation == .deleted); #expect(await history.latestUndoable()?.kind == .calendarUpdate)
        #expect(try await executor.execute(command("Відміни останнє", intent: .undo)).operation == .undone); #expect(await calendar.items.contains { $0.identifier == "event-1" })
    }

    @Test func reminderCreateCompleteDeleteRecordAndUndoAuthoritativeHistory() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let reminders = DirectReminderStub(); let history = ActionHistory(persistence: DirectMemoryHistoryStore())
        let executor = ProductionEventKitCommandExecutor(calendar: DirectCalendarStub(), reminders: reminders, history: history, now: { start }, timeZone: TimeZone(identifier: "Europe/Kyiv")!)
        let created = try await executor.execute(command("Нагадай купити хліб завтра о 12:00", intent: .reminderCreate))
        #expect(created.operation == .created); #expect(await history.latestUndoable()?.kind == .reminderCreate)
        #expect(try await executor.execute(command("Відміни останнє", intent: .undo)).operation == .undone)
        let draft = ReminderDraft(title: "Milk", dueDate: start, notes: nil, priority: 0, timeZoneIdentifier: nil, locationTrigger: nil, listIdentifier: "list-1")
        await reminders.seed(.init(identifier: "r1", draft: draft, isCompleted: false))
        let completed = try await executor.execute(command("Виконай нагадування Milk", intent: .reminderComplete))
        #expect(completed.operation == .completed); #expect(await history.latestUndoable()?.kind == .reminderUpdate)
        #expect(try await executor.execute(command("Відміни останнє", intent: .undo)).operation == .undone); #expect((await reminders.items.first { $0.identifier == "r1" })?.isCompleted == false)
        let deleted = try await executor.execute(command("Видали нагадування Milk", intent: .reminderDelete))
        #expect(deleted.operation == .deleted); #expect(await history.latestUndoable()?.kind == .reminderUpdate)
        #expect(try await executor.execute(command("Відміни останнє", intent: .undo)).operation == .undone); #expect(await reminders.items.contains { $0.identifier == "r1" })
    }

    @Test func relativeReminderCreatesWithCleanTitleAndResolvedDeadline() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let reminders = DirectReminderStub()
        let executor = ProductionEventKitCommandExecutor(calendar: DirectCalendarStub(), reminders: reminders, history: ActionHistory(persistence: DirectMemoryHistoryStore()), now: { start }, timeZone: TimeZone(identifier: "Europe/Kyiv")!)
        let parsed = LocalCommandEngine().parse("Нагадай мені через 10 хвилин вимкнути духовку")
        let result = try await executor.execute(parsed)
        #expect(result.operation == .created)
        let created = try #require(await reminders.items.first)
        #expect(created.draft.title == "вимкнути духовку")
        #expect(created.draft.dueDate?.timeIntervalSince(start) == 600)
    }
}
