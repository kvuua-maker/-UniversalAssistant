import Foundation
import Observation

@MainActor
@Observable
final class AssistantViewModel {
    var input = ""
    var isListening = false
    var voiceInputEnabled = true
    private(set) var statusText = AppText.value("ready")
    private(set) var resultState: AssistantResultState = .idle
    private(set) var interactionDecision: InteractionDecision?
    let recorder = AudioRecorderController()
    private let commandEngine: any CommandParsing
    private let interactionEngine: any InteractionDeciding
    private let voiceInput = VoiceInputController()
    private let feedbackStore: UserFeedbackStore

    init(
        commandEngine: any CommandParsing = LocalCommandEngine(),
        interactionEngine: any InteractionDeciding = InteractionDecisionEngine(),
        feedbackStore: UserFeedbackStore = .shared
    ) {
        self.commandEngine = commandEngine
        self.interactionEngine = interactionEngine
        self.feedbackStore = feedbackStore
    }

    func toggleListening() {
        guard voiceInputEnabled else {
            voiceInput.stop(); isListening = false; statusText = AppText.value("voice_disabled")
            return
        }
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

    func setVoiceInputEnabled(_ enabled: Bool) {
        voiceInputEnabled = enabled
        if !enabled { voiceInput.stop(); isListening = false; statusText = AppText.value("voice_disabled") }
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

    @discardableResult
    func reportWrongResult() async -> UserFeedbackRecord? {
        guard resultState != .idle else { return nil }
        guard let record = try? await feedbackStore.record(.wrongResult) else { return nil }
        statusText = String(format: AppText.feedback("feedback_recorded_format"), record.diagnosticID)
        return record
    }
}
