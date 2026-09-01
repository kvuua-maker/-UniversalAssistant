import Foundation
import Observation

@MainActor
@Observable
final class AssistantViewModel {
    var input = ""
    var isListening = false
    private(set) var statusText = "Готовий"
    private let commandEngine: any CommandParsing

    init(commandEngine: any CommandParsing = LocalCommandEngine()) { self.commandEngine = commandEngine }

    func toggleListening() {
        isListening.toggle()
        statusText = isListening ? "Слухаю…" : "Готовий"
    }

    func submit() {
        let command = commandEngine.parse(input)
        input = ""
        statusText = command.intent == .unknown ? "Потрібне уточнення" : "✓ Готово"
    }
}
