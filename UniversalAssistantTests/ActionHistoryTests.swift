import Foundation
import Testing
@testable import UniversalAssistant

private actor MemoryHistoryPersistence: ActionHistoryPersisting {
    var records: [ActionRecord] = []
    func load() -> [ActionRecord] { records }
    func save(_ records: [ActionRecord]) { self.records = records }
}

private actor UndoSpy: ActionUndoing {
    enum Failure: Error { case rejected }
    var identifiers: [String] = []
    let shouldFail: Bool
    init(shouldFail: Bool = false) { self.shouldFail = shouldFail }
    func undo(_ record: ActionRecord) throws {
        if shouldFail { throw Failure.rejected }
        identifiers.append(record.externalIdentifier)
    }
}

struct ActionHistoryTests {
    @Test func undoUsesLatestCompletedActionAndPersistsTruth() async throws {
        let persistence = MemoryHistoryPersistence()
        let history = ActionHistory(persistence: persistence)
        try await history.record(.init(kind: .calendarCreate, externalIdentifier: "event-1", createdAt: .init(timeIntervalSince1970: 1)))
        try await history.record(.init(kind: .reminderCreate, externalIdentifier: "reminder-2", createdAt: .init(timeIntervalSince1970: 2)))
        let spy = UndoSpy()

        let undone = try await history.undoLast(using: spy)

        #expect(undone.externalIdentifier == "reminder-2")
        #expect(undone.status == .undone)
        #expect(await spy.identifiers == ["reminder-2"])
        #expect(await persistence.records.last?.status == .undone)
    }

    @Test func failedUndoRemainsAvailableAndNeverClaimsSuccess() async throws {
        let history = ActionHistory(persistence: MemoryHistoryPersistence())
        try await history.record(.init(kind: .calendarUpdate, externalIdentifier: "event-1"))

        await #expect(throws: UndoSpy.Failure.self) {
            try await history.undoLast(using: UndoSpy(shouldFail: true))
        }
        #expect(await history.latestUndoable()?.externalIdentifier == "event-1")
    }

    @Test func boundedHistoryDropsOldest() async throws {
        let history = ActionHistory(persistence: MemoryHistoryPersistence(), capacity: 2)
        try await history.record(.init(kind: .noteCreate, externalIdentifier: "1"))
        try await history.record(.init(kind: .noteCreate, externalIdentifier: "2"))
        try await history.record(.init(kind: .noteCreate, externalIdentifier: "3"))
        #expect(await history.snapshot().map(\.externalIdentifier) == ["2", "3"])
    }

    @Test func restoreRecoversInterruptedUndoWithoutExecutingIt() async throws {
        let persistence = MemoryHistoryPersistence()
        await persistence.save([.init(kind: .calendarCreate, externalIdentifier: "event", status: .undoing)])
        let history = ActionHistory(persistence: persistence)
        try await history.restore()
        #expect(await history.latestUndoable()?.externalIdentifier == "event")
    }
}
