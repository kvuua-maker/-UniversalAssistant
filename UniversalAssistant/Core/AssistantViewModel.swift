import Foundation
import Observation

@MainActor
@Observable
final class AssistantViewModel {
    var input = ""
    var isListening = false
    private(set) var statusText = AppText.value("ready")
    private(set) var resultState: AssistantResultState = .idle
    private let commandEngine: any CommandParsing
    private let voiceInput = VoiceInputController()

    init(commandEngine: any CommandParsing = LocalCommandEngine()) { self.commandEngine = commandEngine }

    func toggleListening() {
        if isListening {
            voiceInput.stop(); isListening = false; input = voiceInput.transcript; statusText = AppText.value("ready")
        } else {
            Task {
                await voiceInput.start()
                isListening = voiceInput.state == .listening
                statusText = switch voiceInput.state {
                case .listening: AppText.value("listening")
                case .denied: AppText.value("microphone_denied")
                case .unavailable: AppText.value("speech_unavailable")
                case .failed: AppText.value("listening_failed")
                default: AppText.value("ready")
                }
            }
        }
    }

    func submit() {
        let command = commandEngine.parse(input)
        let summary = ResultSummary(request: command.originalText, intent: command.intent, risk: command.risk)
        input = ""
        if command.needsClarification {
            resultState = .clarification(summary)
            statusText = AppText.value("clarification_needed")
        } else {
            resultState = .completed(summary)
            statusText = AppText.value("done")
        }
    }
}
