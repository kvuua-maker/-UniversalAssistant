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
    private(set) var capabilityPresentation: CapabilityPresentation?
    private(set) var personalTasks: [PersonalTaskItem] = []
    private(set) var favorites: [FavoriteReference] = []
    var presentationPreferences = PresentationPreferences()
    let recorder: AudioRecorderController
    private let commandEngine: any CommandParsing
    private let interactionEngine: any InteractionDeciding
    private let weatherExecutor: any WeatherCommandExecuting
    private let webSearchHandoff: ControlledWebSearchHandoff
    private let genericDiscovery: GenericUnknownRequestCoordinator?
    private let eventKitExecutor: any EventKitCommandExecuting
    private let capabilityExecutor: any CanonicalCapabilityExecuting
    private let voiceInput = VoiceInputController()
    private let feedbackStore: UserFeedbackStore
    private let compactResultDuration: Duration
    private let presentationPreferenceStore: PresentationPreferenceStore
    private var resultDismissTask: Task<Void, Never>?
    private var weatherExecutionInFlight = false
    private var eventKitExecutionInFlight = false

    init(
        commandEngine: any CommandParsing = LocalCommandEngine(),
        interactionEngine: any InteractionDeciding = InteractionDecisionEngine(),
        weatherExecutor: any WeatherCommandExecuting = ProductionWeatherCommandExecutor(),
        webSearchHandoff: ControlledWebSearchHandoff = ControlledWebSearchHandoff(),
        genericDiscovery: GenericUnknownRequestCoordinator? = nil,
        eventKitExecutor: any EventKitCommandExecuting = ProductionEventKitCommandExecutor(),
        capabilityExecutor: (any CanonicalCapabilityExecuting)? = nil,
        recorder: AudioRecorderController = AudioRecorderController(),
        feedbackStore: UserFeedbackStore = .shared,
        compactResultDuration: Duration = .seconds(2),
        presentationPreferenceStore: PresentationPreferenceStore = PresentationPreferenceStore()
    ) {
        self.commandEngine = commandEngine
        self.interactionEngine = interactionEngine
        self.weatherExecutor = weatherExecutor
        self.webSearchHandoff = webSearchHandoff
        self.genericDiscovery = genericDiscovery
        self.eventKitExecutor = eventKitExecutor
        self.capabilityExecutor = capabilityExecutor ?? ProductionCanonicalCapabilityExecutor()
        self.recorder = recorder
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
            if state == .idle, !weatherExecutionInFlight, !eventKitExecutionInFlight, let session = LocalVoiceDiagnosticReport.shared.completedSession() {
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
        let command = commandEngine.parse(input)
        LocalVoiceDiagnosticReport.shared.record(
            "router_received",
            "capability=\(command.intent.rawValue) language=\(command.language.rawValue)"
        )
        let summary = ResultSummary(request: command.originalText, intent: command.intent, risk: command.risk)
        interactionDecision = interactionEngine.decide(for: command)
        input = ""
        if command.needsClarification, command.intent == .unknown {
            presentGeneralInformation(command, summary: summary)
            return
        }
        if command.needsClarification {
            LocalVoiceDiagnosticReport.shared.record("router_rejected", "reason=clarification")
            resultState = .clarification(summary)
            statusText = AppText.value("clarification_needed")
        } else {
            LocalVoiceDiagnosticReport.shared.record("router_accepted", "capability=\(command.intent.rawValue)")
            LocalVoiceDiagnosticReport.shared.record("execution_started", "capability=\(command.intent.rawValue)")
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
            if [.calendarCreate, .calendarQuery, .calendarUpdate, .calendarDelete, .reminderCreate, .reminderQuery, .reminderComplete, .reminderDelete].contains(command.intent) {
                if interactionDecision?.pattern == .confirmation {
                    requireAction(prompt: AppText.value("confirmation_required"), choices: [AppText.value("confirm"), AppText.value("cancel")])
                    LocalVoiceDiagnosticReport.shared.record("router_rejected", "reason=confirmation_required")
                    return
                }
                eventKitExecutionInFlight = true
                resultState = .processing
                statusText = AppText.value("processing")
                LocalVoiceDiagnosticReport.shared.record("execution_started", "mechanism=eventkit")
                Task { [weak self] in
                    guard let self else { return }
                    do {
                        let result = try await eventKitExecutor.execute(command)
                        resultState = .eventKit(result)
                        statusText = AppText.value("ready")
                        LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=eventkit")
                    } catch EventKitExecutionError.unresolvedDateTime, EventKitExecutionError.missingSubject, EventKitExecutionError.ambiguousItem {
                        resultState = .clarification(summary)
                        statusText = AppText.value("clarification_needed")
                    } catch {
                        presentFailure(message: String(localized: "eventkit_unavailable"))
                    }
                    eventKitExecutionInFlight = false
                    if let session = LocalVoiceDiagnosticReport.shared.completedSession() {
                        Task { await PhysicalDiagnosticDelivery.shared.enqueue(session) }
                    }
                }
                return
            }
            if command.intent == .audioRecord {
                let action = AudioRecorderCommand(rawValue: command.entities["recorder_action"] ?? "start") ?? .start
                resultState = .processing
                statusText = AppText.value("processing")
                Task { [weak self] in
                    guard let self else { return }
                    await recorder.execute(action)
                    if recorder.state == .failed || recorder.state == .denied {
                        presentFailure(message: AppText.value("request_unavailable"))
                        LocalVoiceDiagnosticReport.shared.record("execution_failed", "capability=audio_record")
                    } else {
                        resultState = .recognized(summary)
                        statusText = AppText.value("ready")
                        LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=audio_record state=\(String(describing: recorder.state))")
                    }
                }
                return
            }
            if command.intent == .webSearch || command.intent == .unknown {
                presentGeneralInformation(command, summary: summary)
                return
            }
            if interactionDecision?.pattern == .confirmation {
                requireAction(prompt: AppText.value("confirmation_required"), choices: [AppText.value("confirm"), AppText.value("cancel")])
                LocalVoiceDiagnosticReport.shared.record("router_rejected", "reason=confirmation_required")
                return
            }
            executeCanonicalCapability(command, summary: summary)
        }
    }

    private func presentGeneralInformation(_ command: StructuredCommand, summary: ResultSummary) {
        do {
            _ = try GenericIntentParser().parse(command.originalText)
        } catch GenericDiscoveryError.ambiguous {
            resultState = .clarification(summary)
            statusText = AppText.value("clarification_needed")
            return
        } catch {
            presentFailure(message: AppText.value("request_unavailable"))
            return
        }
        guard let genericDiscovery else {
            presentGeneralWebFallback(command)
            return
        }
        resultState = .processing
        statusText = AppText.value("processing")
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await genericDiscovery.execute(text: command.originalText, parsed: command)
                resultState = .deterministic(result)
                statusText = AppText.value("ready")
                LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=deterministic_general_information")
            } catch GenericDiscoveryError.ambiguous {
                resultState = .clarification(summary)
                statusText = AppText.value("clarification_needed")
            } catch {
                presentGeneralWebFallback(command)
            }
        }
    }

    private func presentGeneralWebFallback(_ command: StructuredCommand) {
        do {
            let intent = try GenericIntentParser().parse(command.originalText)
            let minimized = try GenericQuerySanitizer().query(for: intent)
            let safe = StructuredCommand(originalText: minimized, normalizedText: minimized.lowercased(), language: command.language, intent: .unknown)
            let destination = try webSearchHandoff.destination(for: safe, structuredCapabilityAvailable: false)
            resultState = .webHandoff(.init(query: command.originalText, destination: destination))
            statusText = AppText.value("ready")
            LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=web_handoff_fallback")
        } catch {
            presentFailure(message: AppText.value("request_unavailable"))
        }
    }

    private func executeCanonicalCapability(_ command: StructuredCommand, summary: ResultSummary) {
        resultState = .processing
        statusText = AppText.value("processing")
        Task { [weak self] in
            guard let self else { return }
            do {
                switch try await capabilityExecutor.execute(command) {
                case let .result(result):
                    resultState = .deterministic(result)
                    LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=deterministic capability=\(command.intent.rawValue)")
                case let .handoff(result):
                    resultState = .webHandoff(result)
                    LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=handoff capability=\(command.intent.rawValue)")
                case let .presentation(presentation):
                    capabilityPresentation = presentation
                    resultState = .recognized(summary)
                    LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=system_presentation capability=\(command.intent.rawValue)")
                }
                statusText = AppText.value("ready")
            } catch let CanonicalCapabilityExecutionError.ambiguous(values) {
                requireAction(prompt: AppText.value("clarification_needed"), choices: Array(values.prefix(3)))
                statusText = AppText.value("clarification_needed")
            } catch let CanonicalCapabilityExecutionError.missingParameter(parameter) {
                LocalVoiceDiagnosticReport.shared.record("router_rejected", "reason=missing_parameter parameter=\(parameter)")
                resultState = .clarification(summary)
                statusText = AppText.value("clarification_needed")
            } catch let CanonicalCapabilityExecutionError.externalProviderRequired(providerClass) {
                LocalVoiceDiagnosticReport.shared.record("execution_failed", "reason=external_provider_required capability=\(providerClass)")
                presentFailure(message: AppText.value("request_unavailable"))
            } catch {
                LocalVoiceDiagnosticReport.shared.record("execution_failed", "reason=capability_unavailable capability=\(command.intent.rawValue)")
                presentFailure(message: AppText.value("request_unavailable"))
            }
        }
    }

    func dismissCapabilityPresentation() { capabilityPresentation = nil }

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
