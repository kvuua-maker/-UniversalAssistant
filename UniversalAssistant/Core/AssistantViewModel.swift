import Foundation
import Observation

@MainActor
@Observable
final class AssistantViewModel {
    var input = ""
    var isListening = false
    private(set) var statusText = AppText.value("ready")
    private(set) var resultState: AssistantResultState = .idle
    private(set) var interactionDecision: InteractionDecision?
    let recorder = AudioRecorderController()
    private let commandEngine: any CommandParsing
    private let interactionEngine: any InteractionDeciding
    private let voiceInput = VoiceInputController()

    init(
        commandEngine: any CommandParsing = LocalCommandEngine(),
        interactionEngine: any InteractionDeciding = InteractionDecisionEngine()
    ) {
        self.commandEngine = commandEngine
        self.interactionEngine = interactionEngine
    }

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
        interactionDecision = interactionEngine.decide(for: command)
        input = ""
        if command.needsClarification {
            resultState = .clarification(summary)
            statusText = AppText.value("clarification_needed")
        } else {
            resultState = .recognized(summary)
            statusText = AppText.value("request_recognized")
        }
    }
}
