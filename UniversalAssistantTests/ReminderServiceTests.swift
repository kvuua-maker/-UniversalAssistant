import Foundation
import Testing
@testable import UniversalAssistant

private actor ReminderSpy: ReminderMutating {
    var deleted: [String] = []
    var restored: [ReminderSnapshot] = []
    func delete(identifier: String) { deleted.append(identifier) }
    func restore(_ snapshot: ReminderSnapshot) -> ReminderSnapshot {
        restored.append(snapshot)
        return snapshot
    }
}

struct ReminderServiceTests {
    @Test func draftValidationRejectsEmptyTitleAndInvalidPriority() {
        #expect(throws: ReminderServiceError.invalidTitle) { try ReminderDraft(title: " ").validated() }
        #expect(throws: ReminderServiceError.invalidPriority) { try ReminderDraft(title: "Call", priority: 10).validated() }
        #expect(throws: Never.self) { try ReminderDraft(title: "Call", priority: 1).validated() }
    }

    @Test func locationReminderRequiresValidTypedGeofence() throws {
        let valid = ReminderLocationTrigger(title: "Store", latitude: 50.45, longitude: 30.52,
                                            radius: 100, proximity: .enter)
        #expect(try ReminderDraft(title: "Buy milk", locationTrigger: valid).validated().locationTrigger == valid)
        let invalid = ReminderLocationTrigger(title: "", latitude: 100, longitude: 30.52,
                                              radius: 0, proximity: .leave)
        #expect(throws: ReminderServiceError.invalidLocation) {
            try ReminderDraft(title: "Buy milk", locationTrigger: invalid).validated()
        }
    }

    @Test func undoCreatedReminderDeletesExactIdentifier() async throws {
        let spy = ReminderSpy()
        try await ReminderActionUndoHandler(reminders: spy).undo(
            .init(kind: .reminderCreate, externalIdentifier: "reminder-3")
        )
        #expect(await spy.deleted == ["reminder-3"])
    }

    @Test func undoUpdatedReminderRestoresSnapshot() async throws {
        let spy = ReminderSpy()
        let previous = ReminderSnapshot(identifier: "r1", draft: .init(title: "Original", priority: 5), isCompleted: false)
        try await ReminderActionUndoHandler(reminders: spy).undo(
            .init(kind: .reminderUpdate, externalIdentifier: "r1", undoPayload: try JSONEncoder().encode(previous))
        )
        #expect(await spy.restored == [previous])
    }

    @Test func unrelatedActionCannotUseReminderUndo() async {
        await #expect(throws: ActionHistoryError.nothingToUndo) {
            try await ReminderActionUndoHandler(reminders: ReminderSpy()).undo(
                .init(kind: .calendarCreate, externalIdentifier: "event")
            )
        }
    }
}
