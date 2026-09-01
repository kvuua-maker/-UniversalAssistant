import Testing
@testable import UniversalAssistant

struct LocalActionRouterTests {
    private let router = LocalActionRouter()

    @Test func shoppingListUsesSystemRemindersWithoutDuplication() {
        #expect(route(.shoppingList) == .init(
            target: .eventKitReminders,
            depth: .direct,
            reason: "system_first_reminders"
        ))
    }

    @Test func notesUseTruthfulHandoffRatherThanInventedDirectAPI() {
        let result = route(.noteCreate)
        #expect(result.target == .systemShareHandoff)
        #expect(result.depth == .handoff)
    }

    @Test("Known local verticals route to public adapters", arguments: [
        (CommandIntent.calendarCreate, LocalIntegrationTarget.eventKitCalendar),
        (.reminderCreate, .eventKitReminders),
        (.contactLookup, .contacts),
        (.audioRecord, .internalAudioRecorder)
    ])
    func knownRoutes(_ intent: CommandIntent, _ target: LocalIntegrationTarget) {
        #expect(route(intent).target == target)
        #expect(route(intent).depth == .direct)
    }

    @Test func unsupportedIntentNeverPretendsToExecute() {
        #expect(route(.taxiSearch).depth == .unavailable)
    }

    private func route(_ intent: CommandIntent) -> LocalActionRoute {
        router.route(.init(originalText: "test", normalizedText: "test", language: .en, intent: intent))
    }
}
