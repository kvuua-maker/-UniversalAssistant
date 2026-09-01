import AppIntents

struct StartAssistantIntent: AppIntent {
    static let title: LocalizedStringResource = "Start UniversalAssistant"
    static let description = IntentDescription("Open UniversalAssistant ready for a voice or typed command.")
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult { .result() }
}

struct UniversalAssistantShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartAssistantIntent(), phrases: ["Start \(.applicationName)", "Ask \(.applicationName)"], shortTitle: "Start Assistant", systemImageName: "mic.circle")
    }
}
