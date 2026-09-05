import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class AssistantViewModel {
    private static let voiceLogger = Logger(subsystem: "com.universalassistant.app", category: "VoicePipeline")
    var input = ""
    var isListening = false
    var voiceInputEnabled = true
    private(set) var statusText = AppText.value("ready")
    private(set) var resultState: AssistantResultState = .idle
    private(set) var shouldOfferSettings = false
    private(set) var interactionDecision: InteractionDecision?
    private(set) var personalTasks: [PersonalTaskItem] = []
    private(set) var favorites: [FavoriteReference] = []
    var presentationPreferences = PresentationPreferences()
    let recorder = AudioRecorderController()
    private let commandEngine: any CommandParsing
    private let interactionEngine: any InteractionDeciding
    private let weatherExecutor: any WeatherCommandExecuting
    private let voiceInput = VoiceInputController()
    private let feedbackStore: UserFeedbackStore
    private let compactResultDuration: Duration
    private let presentationPreferenceStore: PresentationPreferenceStore
    private var resultDismissTask: Task<Void, Never>?
    private var weatherExecutionInFlight = false

    init(
        commandEngine: any CommandParsing = LocalCommandEngine(),
        interactionEngine: any InteractionDeciding = InteractionDecisionEngine(),
        weatherExecutor: any WeatherCommandExecuting = ProductionWeatherCommandExecutor(),
        feedbackStore: UserFeedbackStore = .shared,
        compactResultDuration: Duration = .seconds(2),
        presentationPreferenceStore: PresentationPreferenceStore = PresentationPreferenceStore()
    ) {
        self.commandEngine = commandEngine
        self.interactionEngine = interactionEngine
        self.weatherExecutor = weatherExecutor
        self.feedbackStore = feedbackStore
        self.compactResultDuration = compactResultDuration
        self.presentationPreferenceStore = presentationPreferenceStore
        voiceInput.setEventHandler { [weak self] event in
            self?.handleVoiceEvent(event)
        }
        Task { [weak self] in
            guard let self else { return }
            if let value = try? await presentationPreferenceStore.load() { self.presentationPreferences = value }
        }
    }

    func toggleListening() {
        guard voiceInputEnabled else {
            voiceInput.stop(reason: .voiceDisabled); isListening = false; statusText = AppText.value("voice_disabled")
            return
        }
        if isListening {
            voiceInput.stop(reason: .userPressedStop); isListening = false; input = voiceInput.transcript; statusText = AppText.value("ready")
        } else {
            Task {
                await voiceInput.start()
                applyVoiceState(voiceInput.state)
            }
        }
    }

    func applyVoiceState(_ state: VoiceInputState) {
        isListening = state == .listening
        shouldOfferSettings = state == .denied
        statusText = switch state {
                case .listening: AppText.value("listening")
                case .denied: AppText.value("microphone_denied")
                case .unavailable: AppText.value("speech_unavailable")
                case .failed: AppText.value("listening_failed")
                default: AppText.value("ready")
        }
    }

    func handleVoiceEvent(_ event: VoiceInputEvent) {
        switch event {
        case let .state(state):
            LocalVoiceDiagnosticReport.shared.record("state_delivered_to_view_model", "state=\(String(describing: state))")
            applyVoiceState(state)
            if state == .idle, !weatherExecutionInFlight, let session = LocalVoiceDiagnosticReport.shared.completedSession() {
                Task { await PhysicalDiagnosticDelivery.shared.enqueue(session) }
            }
        case let .transcript(transcript, isFinal):
            input = transcript
            LocalVoiceDiagnosticReport.shared.record("transcript_delivered_to_view_model", "length=\(transcript.count) final=\(isFinal)")
            Self.voiceLogger.notice("transcript_delivered_to_view_model length=\(transcript.count, privacy: .public) final=\(isFinal, privacy: .public)")
            if isFinal, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Self.voiceLogger.notice("transcript_delivered_to_router")
                LocalVoiceDiagnosticReport.shared.record("transcript_delivered_to_router", "length=\(transcript.count)")
                submit()
            }
        }
    }

    func voiceDiagnosticReport() -> String {
        LocalVoiceDiagnosticReport.shared.snapshot()
    }

    func handleQuickLaunch() {
        guard QuickLaunchRequestStore().consumeVoiceLaunch() else { return }
        guard voiceInputEnabled else { statusText = AppText.value("voice_disabled"); return }
        toggleListening()
    }

    func savePresentationPreferences(_ value: PresentationPreferences) {
        presentationPreferences = value
        Task { try? await presentationPreferenceStore.save(value) }
    }

    func setVoiceInputEnabled(_ enabled: Bool) {
        voiceInputEnabled = enabled
        if !enabled { voiceInput.stop(reason: .voiceDisabled); isListening = false; statusText = AppText.value("voice_disabled") }
    }

    func handleSceneBecameInactive() {
        voiceInput.stop(reason: .sceneInactive)
        isListening = false
        resultDismissTask?.cancel()
    }

    func submit() {
        resultDismissTask?.cancel()
        LocalVoiceDiagnosticReport.shared.record("router_received")
        let command = commandEngine.parse(input)
        let summary = ResultSummary(request: command.originalText, intent: command.intent, risk: command.risk)
        interactionDecision = interactionEngine.decide(for: command)
        input = ""
        if command.needsClarification {
            LocalVoiceDiagnosticReport.shared.record("router_rejected", "reason=clarification")
            resultState = .clarification(summary)
            statusText = AppText.value("clarification_needed")
        } else {
            LocalVoiceDiagnosticReport.shared.record("router_accepted")
            LocalVoiceDiagnosticReport.shared.record("execution_started")
            if command.intent == .weather {
                weatherExecutionInFlight = true
                resultState = .processing
                statusText = AppText.value("processing")
                Task { [weak self] in
                    guard let self else { return }
                    do {
                        let snapshot = try await weatherExecutor.execute(command)
                        resultState = .weather(snapshot)
                        LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=weather")
                        statusText = AppText.value("ready")
                    } catch {
                        LocalVoiceDiagnosticReport.shared.record(
                            "execution_failed",
                            "capability=weather error=\(String(describing: type(of: error)))"
                        )
                        let unavailable = String(localized: "weather_unavailable", table: "Weather")
                        let retry = String(localized: "weather_retry", table: "Weather")
                        presentFailure(message: unavailable, recoveryAction: retry)
                        statusText = unavailable
                    }
                    weatherExecutionInFlight = false
                    if let session = LocalVoiceDiagnosticReport.shared.completedSession() {
                        Task { await PhysicalDiagnosticDelivery.shared.enqueue(session) }
                    }
                }
                return
            }
            resultState = .recognized(summary)
            LocalVoiceDiagnosticReport.shared.record("visible_result")
            statusText = AppText.value("request_recognized")
            if interactionDecision?.pattern == .compactAcknowledgement {
                let duration = compactResultDuration
                resultDismissTask = Task { [weak self] in
                    try? await Task.sleep(for: duration)
                    guard !Task.isCancelled else { return }
                    self?.resultState = .idle
                    self?.statusText = AppText.value("ready")
                }
            }
        }
    }

    func beginProcessing() {
        resultDismissTask?.cancel()
        resultState = .processing
        statusText = AppText.value("processing")
    }

    func requireAction(prompt: String, choices: [String]) {
        resultDismissTask?.cancel()
        resultState = .actionRequired(.init(prompt: prompt, choices: choices))
    }

    func presentFailure(message: String, recoveryAction: String? = nil) {
        resultDismissTask?.cancel()
        resultState = .failure(.init(message: message, recoveryAction: recoveryAction))
    }

    func presentExpanded(_ summary: ResultSummary) {
        resultDismissTask?.cancel()
        resultState = .expanded(summary)
    }

    func ingestShared(_ envelope: SharedInboxEnvelope) {
        switch envelope.kind {
        case "url", "text":
            input = envelope.value
        case "vcard":
            input = "Використай переданий контакт"
        case "image":
            input = "Опрацюй передане зображення"
        case "document":
            input = "Опрацюй переданий документ"
        default:
            return
        }
        submit()
    }

    @discardableResult
    func reportWrongResult() async -> UserFeedbackRecord? {
        guard resultState != .idle else { return nil }
        guard let record = try? await feedbackStore.record(.wrongResult) else { return nil }
        statusText = String(format: AppText.feedback("feedback_recorded_format"), record.diagnosticID)
        return record
    }
}
