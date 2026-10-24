import AppIntents

struct StartAssistantIntent: AppIntent {
    static let title: LocalizedStringResource = "Start UniversalAssistant"
    static let description = IntentDescription("Open UniversalAssistant ready for a voice or typed command.")
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        QuickLaunchRequestStore().requestVoiceLaunch()
        return .result()
    }
}

struct RunAssistantCommandIntent: AppIntent {
    static let title: LocalizedStringResource = "Run a command in UniversalAssistant"
    static let description = IntentDescription("Send a command through the same canonical UniversalAssistant pipeline used by typed and voice input.")
    static let openAppWhenRun = true

    @Parameter(title: "Command") var command: String
    private var requestStore = QuickLaunchRequestStore()
    static var parameterSummary: some ParameterSummary { Summary("Run \(\.$command)") }

    init() {}
    init(command: String) { self.command = command }
    init(command: String, requestStore: QuickLaunchRequestStore) {
        self.command = command
        self.requestStore = requestStore
    }

    func perform() async throws -> some IntentResult {
        requestStore.requestCommand(command)
        return .result()
    }
}

struct OpenAssistantForTypingIntent: AppIntent {
    static let title: LocalizedStringResource = "Open UniversalAssistant for typing"
    static let description = IntentDescription("Open UniversalAssistant without starting the microphone.")
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult { .result() }
}

struct UniversalAssistantShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartAssistantIntent(), phrases: ["Start \(.applicationName)", "Ask \(.applicationName)"], shortTitle: "Start Assistant", systemImageName: "mic.circle")
        AppShortcut(intent: OpenAssistantForTypingIntent(), phrases: ["Open \(.applicationName) for typing", "Type in \(.applicationName)"], shortTitle: "Type a Command", systemImageName: "keyboard")
        AppShortcut(intent: RunAssistantCommandIntent(), phrases: ["Ask \(.applicationName) to open an app", "Run a command in \(.applicationName)"], shortTitle: "Run a Command", systemImageName: "text.bubble")
    }
}
