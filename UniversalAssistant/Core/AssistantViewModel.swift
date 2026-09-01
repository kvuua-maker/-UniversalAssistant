import Foundation
import Observation

@MainActor
@Observable
final class AssistantViewModel {
    var input = ""
    var isListening = false
    private(set) var statusText = "Готовий"
    private let commandEngine: any CommandParsing
    private let voiceInput = VoiceInputController()

    init(commandEngine: any CommandParsing = LocalCommandEngine()) { self.commandEngine = commandEngine }

    func toggleListening() {
        if isListening {
            voiceInput.stop(); isListening = false; input = voiceInput.transcript; statusText = "Готовий"
        } else {
            Task {
                await voiceInput.start()
                isListening = voiceInput.state == .listening
                statusText = switch voiceInput.state {
                case .listening: "Слухаю…"
                case .denied: "Дозвіл на мікрофон вимкнено"
                case .unavailable: "Розпізнавання недоступне"
                case .failed: "Не вдалося почати слухання"
                default: "Готовий"
                }
            }
        }
    }

    func submit() {
        let command = commandEngine.parse(input)
        input = ""
        statusText = command.intent == .unknown ? "Потрібне уточнення" : "✓ Готово"
    }
}
