import CryptoKit
import Foundation
import Observation
import OSLog
import UIKit

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
    private let currentContext: CurrentContextStore
    private let ocrPipeline: OCRProductionPipeline
    private let voiceInput: VoiceInputController
    private let feedbackStore: UserFeedbackStore
    private let compactResultDuration: Duration
    private let presentationPreferenceStore: PresentationPreferenceStore
    private let systemHandoffOpen:  (URL) -> Void
    private let quickLaunchStore: QuickLaunchRequestStore
    private let notificationEnable: @MainActor () async -> ProactiveNotificationEnableResult
    private var resultDismissTask: Task<Void, Never>?
    private var weatherExecutionInFlight = false
    private var eventKitExecutionInFlight = false
    private var capabilityExecutionInFlight = false
    private var activeRequestGeneration: UInt64 = 0
    private var capabilityExecutionTask: Task<Void, Never>?
    private var ocrExecutionTask: Task<Void, Never>?
    private var weatherExecutionTask: Task<Void, Never>?
    private var eventKitExecutionTask: Task<Void, Never>?
    private var genericDiscoveryTask: Task<Void, Never>?
    private var capabilityContinuation: CanonicalCapabilityContinuation?
    private var capabilityPresentationGeneration: UInt64?
    private var capabilityPresentationCommandID: UUID?
    // Own the permission-suspending microphone start from the UI lifecycle.
    // Controller generation guards suppress stale callbacks; this task ownership
    // also prevents abandoned starts surviving re-entry or scene transitions.
    private var voiceStartTask: Task<Void, Never>?
    private var pendingVoiceRecognitionEvidence: VoiceRecognitionEvidence?
    private var pendingConfirmation: (command: StructuredCommand, summary: ResultSummary, generation: UInt64)?
    private var pendingCanonicalSelection: (command: StructuredCommand, summary: ResultSummary, generation: UInt64, role: String, choices: [String])?

    init(
        commandEngine: any CommandParsing = LanguageUnderstandingBlock(),
        interactionEngine: any InteractionDeciding = InteractionDecisionEngine(),
        weatherExecutor: any WeatherCommandExecuting = ProductionWeatherCommandExecutor(),
        webSearchHandoff: ControlledWebSearchHandoff = ControlledWebSearchHandoff(),
        genericDiscovery: GenericUnknownRequestCoordinator? = nil,
        eventKitExecutor: any EventKitCommandExecuting = ProductionEventKitCommandExecutor(),
        capabilityExecutor: (any CanonicalCapabilityExecuting)? = nil,
        currentContext suppliedCurrentContext: CurrentContextStore? = nil,
        ocrProcessor: (any DocumentOCRProcessing)? = nil,
        recorder: AudioRecorderController = AudioRecorderController(),
        feedbackStore: UserFeedbackStore = .shared,
        compactResultDuration: Duration = .seconds(2),
        presentationPreferenceStore: PresentationPreferenceStore = PresentationPreferenceStore(),
        voiceInput: VoiceInputController = VoiceInputController(),
        notificationEnable: @escaping @MainActor () async -> ProactiveNotificationEnableResult = { await ProductionNotificationRegistration.enable() },
        quickLaunchStore: QuickLaunchRequestStore = QuickLaunchRequestStore(),
        systemHandoffOpen: @escaping @MainActor (URL) -> Void = { UIApplication.shared.open($0) }
    ) {
        self.commandEngine = commandEngine
        self.interactionEngine = interactionEngine
        self.weatherExecutor = weatherExecutor
        self.webSearchHandoff = webSearchHandoff
        self.genericDiscovery = genericDiscovery
        self.eventKitExecutor = eventKitExecutor
        let currentContext = suppliedCurrentContext ?? CurrentContextStore()
        self.currentContext = currentContext
        self.capabilityExecutor = capabilityExecutor ?? ProductionCanonicalCapabilityExecutor(currentContext: currentContext, recorder: recorder)
        self.ocrPipeline = OCRProductionPipeline(processor: ocrProcessor ?? OnDeviceDocumentOCR())
        self.recorder = recorder
        self.feedbackStore = feedbackStore
        self.compactResultDuration = compactResultDuration
        self.presentationPreferenceStore = presentationPreferenceStore
        self.voiceInput = voiceInput
        self.notificationEnable = notificationEnable
        self.quickLaunchStore = quickLaunchStore
        self.systemHandoffOpen = systemHandoffOpen
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
        if isListening || voiceInput.state == .requestingPermission {
            voiceStartTask?.cancel()
            voiceStartTask = nil
            voiceInput.stop(reason: .userPressedStop); isListening = false; input = voiceInput.transcript; statusText = AppText.value("ready")
        } else {
            voiceStartTask?.cancel()
            voiceStartTask = Task { [weak self] in
                guard let self else { return }
                await voiceInput.start()
                guard !Task.isCancelled else { return }
                applyVoiceState(voiceInput.state)
                voiceStartTask = nil
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
            if state == .idle, !weatherExecutionInFlight, !eventKitExecutionInFlight, !capabilityExecutionInFlight, let session = LocalVoiceDiagnosticReport.shared.completedSession() {
                Task { await PhysicalDiagnosticDelivery.shared.enqueue(session) }
            }
        case let .recognitionEvidence(evidence):
            pendingVoiceRecognitionEvidence = evidence
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
        if let command = quickLaunchStore.consumeCommand() {
            input = command
            submit()
            return
        }
        guard quickLaunchStore.consumeVoiceLaunch() else { return }
        guard voiceInputEnabled else { statusText = AppText.value("voice_disabled"); return }
        toggleListening()
    }

    func savePresentationPreferences(_ value: PresentationPreferences) {
        presentationPreferences = value
        Task { try? await presentationPreferenceStore.save(value) }
    }

    func enableProactiveNotifications() async {
        switch await notificationEnable() {
        case .enabled: statusText = "Сповіщення ввімкнено"
        case .denied: statusText = "Дозвіл на сповіщення не надано"
        case .failed: statusText = AppText.value("request_unavailable")
        }
    }

    func setVoiceInputEnabled(_ enabled: Bool) {
        voiceInputEnabled = enabled
        if !enabled { voiceInput.stop(reason: .voiceDisabled); isListening = false; statusText = AppText.value("voice_disabled") }
    }

    func handleSceneBecameInactive() {
        recorder.finalizeForLifecycleTransition()
        voiceStartTask?.cancel()
        voiceStartTask = nil
        LocalVoiceDiagnosticReport.shared.record("scene_transition", "state=inactive")
        voiceInput.stop(reason: .sceneInactive)
        isListening = false
        resultDismissTask?.cancel()
    }

    func submit() {
        let voiceEvidence = pendingVoiceRecognitionEvidence
        pendingVoiceRecognitionEvidence = nil
        resultDismissTask?.cancel()
        activeRequestGeneration &+= 1
        let requestGeneration = activeRequestGeneration
        if LocalVoiceDiagnosticReport.shared.finishInteractiveContinuation(.cancelled, details: "reason=superseded") {
            deliverCompletedDiagnosticSession()
        }
        LocalVoiceDiagnosticReport.shared.beginHomeRequest(generation: requestGeneration)
        capabilityExecutionTask?.cancel()
        ocrExecutionTask?.cancel()
        weatherExecutionTask?.cancel()
        eventKitExecutionTask?.cancel()
        genericDiscoveryTask?.cancel()
        // A newly submitted command supersedes any UI-bound continuation.
        // Late picker/scanner/OCR callbacks therefore cannot resume an obsolete request.
        capabilityContinuation = nil
        capabilityPresentationGeneration = nil
        capabilityPresentationCommandID = nil
        capabilityPresentation = nil
        pendingConfirmation = nil
        pendingCanonicalSelection = nil
        weatherExecutionInFlight = false
        eventKitExecutionInFlight = false
        capabilityExecutionInFlight = false
        let submittedInput = input
        LocalVoiceDiagnosticReport.shared.recordSubmittedInputIfNeeded(submittedInput)
        if let target = translationFollowUpTarget(submittedInput), let translation = currentContext.freshTranslation() {
            input = ""
            startTranslation(translation.sourceText, target)
            return
        }
        if isSharedImageTextRequest(submittedInput), let shared = currentContext.freshShared(), shared.kind == .image,
           let data = SharedInboxStore.imageData(from: shared.value), let image = UIImage(data: data) {
            input = ""
            processOCR(image, provenance: .sharedImage)
            return
        }
        if isSharedImageTextRequest(submittedInput), let identifier = currentContext.freshPhotoAssetIdentifier() {
            input = ""
            LocalVoiceDiagnosticReport.shared.suspendForInteractiveContinuation("photo-asset", generation: requestGeneration)
            capabilityPresentation = .photoAsset(identifier)
            LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=system_presentation capability=photoSearch")
            return
        }
        if isSharedURLOpenRequest(submittedInput), let shared = currentContext.freshShared(), shared.kind == .url,
           let url = URL(string: shared.value) {
            input = ""
            resultState = .webHandoff(.init(query: url.host ?? shared.value, destination: url, kind: .system))
            statusText = AppText.value("ready")
            LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=current_context_url")
            deliverCompletedDiagnosticSession()
            return
        }
        let command = if let parser = commandEngine as? any EvidenceAwareCommandParsing {
            parser.parse(submittedInput, speechEvidence: voiceEvidence)
        } else {
            commandEngine.parse(submittedInput)
        }
        LocalVoiceDiagnosticReport.shared.recordNormalizedTranscript(command.normalizedText)
        LocalVoiceDiagnosticReport.shared.record("language_detection", "language=\(command.language.rawValue)")
        LocalVoiceDiagnosticReport.shared.record("morphology", "status=completed")
        let structuredNumberCount = command.entities.keys.filter {
            $0.contains("number") || $0.contains("amount") || $0.contains("duration") || $0 == "time"
        }.count
        LocalVoiceDiagnosticReport.shared.record("structured_number_reconstruction", "count=\(structuredNumberCount)")
        let entityDomain = command.entities["entity_domain"] ?? command.entities["catalog_entity_kind"] ?? "canonical"
        let entityCandidateCount = command.entities["entity_candidate_count"] ?? command.entities["speech_alternative_count"] ?? "0"
        let entityConfidence = command.entities["entity_confidence"] ?? command.entities["semantic_confidence"] ?? "unavailable"
        LocalVoiceDiagnosticReport.shared.record("entity_recovery", "domain=\(entityDomain) candidate_count=\(entityCandidateCount) confidence=\(entityConfidence)")
        LocalVoiceDiagnosticReport.shared.record("entity_domain", "domain=\(entityDomain)")
        LocalVoiceDiagnosticReport.shared.record(
            "entity_candidates",
            "candidate_count=\(entityCandidateCount) candidate_fingerprints=\(Self.diagnosticCandidateFingerprints(command.entities["clarification_options"]))"
        )
        LocalVoiceDiagnosticReport.shared.record("entity_confidence", "confidence=\(entityConfidence)")
        let constraintCount = [
            command.constraints.maximumPrice != nil, command.constraints.currency != nil, command.constraints.size != nil,
            command.constraints.color != nil, command.constraints.brand != nil, command.constraints.category != nil,
            command.constraints.season != nil, command.constraints.ordinal != nil, command.constraints.maximumWaitMinutes != nil
        ].filter { $0 }.count + command.constraints.hardConstraintKeys.count
        LocalVoiceDiagnosticReport.shared.record(
            "canonical_semantic_frame",
            diagnosticSemanticFrameDetails(for: command, constraintCount: constraintCount)
        )
        LocalVoiceDiagnosticReport.shared.record("candidate_capabilities", "count=1 capability=\(command.intent.rawValue)")
        LocalVoiceDiagnosticReport.shared.record("selected_capability", "capability=\(command.intent.rawValue)")
        let genericWeb = command.intent == .webSearch
        LocalVoiceDiagnosticReport.shared.record("system_first_decision", "selected=\(!genericWeb) capability=\(command.intent.rawValue)")
        LocalVoiceDiagnosticReport.shared.record("generic_web_selected", "selected=\(genericWeb) reason=\(genericWeb ? "structured_general_or_web_intent" : "canonical_non_web_intent")")
        LocalVoiceDiagnosticReport.shared.record(
            "current_context_input",
            "input_type=\(currentContext.diagnosticInputType())"
        )
        LocalVoiceDiagnosticReport.shared.record(
            "router_received",
            "capability=\(command.intent.rawValue) language=\(command.language.rawValue)"
        )
        let summary = ResultSummary(request: command.originalText, intent: command.intent, risk: command.risk)
        interactionDecision = interactionEngine.decide(for: command)
        input = ""
        if command.needsClarification {
            LocalVoiceDiagnosticReport.shared.record("router_rejected", "reason=clarification")
            if let raw = command.entities["clarification_options"] {
                let choices = Array(raw.split(separator: "|").map(String.init).prefix(3))
                pendingCanonicalSelection = (
                    command, summary, requestGeneration,
                    command.entities["clarification_role"] ?? Self.selectionRole(for: command, choices: choices),
                    choices
                )
                LocalVoiceDiagnosticReport.shared.suspendForInteractiveContinuation("canonical-clarification", generation: requestGeneration)
                requireAction(prompt: AppText.value("clarification_needed"), choices: choices)
            } else {
                resultState = .clarification(summary)
                LocalVoiceDiagnosticReport.shared.recordTerminal(.clarification)
                deliverCompletedDiagnosticSession()
            }
            statusText = AppText.value("clarification_needed")
        } else {
            LocalVoiceDiagnosticReport.shared.record("router_accepted", "capability=\(command.intent.rawValue)")
            LocalVoiceDiagnosticReport.shared.record("execution_started", "capability=\(command.intent.rawValue)")
            if command.intent == .weather {
                weatherExecutionInFlight = true
                resultState = .processing
                statusText = AppText.value("processing")
                weatherExecutionTask = Task { [weak self] in
                    guard let self else { return }
                    defer {
                        if activeRequestGeneration == requestGeneration {
                            weatherExecutionInFlight = false
                            deliverCompletedDiagnosticSession()
                        }
                    }
                    do {
                        let snapshot = try await weatherExecutor.execute(command)
                        try Task.checkCancellation()
                        guard activeRequestGeneration == requestGeneration else { return }
                        resultState = .weather(snapshot)
                        LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=weather")
                        statusText = AppText.value("ready")
                    } catch {
                        guard !Task.isCancelled, activeRequestGeneration == requestGeneration else { return }
                        LocalVoiceDiagnosticReport.shared.record(
                            "execution_failed",
                            "capability=weather error=\(String(describing: type(of: error)))"
                        )
                        let unavailable = String(localized: "weather_unavailable", table: "Weather")
                        let retry = String(localized: "weather_retry", table: "Weather")
                        presentFailure(message: unavailable, recoveryAction: retry)
                        statusText = unavailable
                    }
                }
                return
            }
            if [.calendarCreate, .calendarQuery, .calendarDelete, .reminderCreate, .reminderQuery, .reminderComplete, .reminderDelete, .shoppingList, .undo].contains(command.intent) {
                if interactionDecision?.pattern == .confirmation {
                    requireConfirmation(command, summary: summary, generation: requestGeneration)
                    return
                }
                eventKitExecutionInFlight = true
                resultState = .processing
                statusText = AppText.value("processing")
                LocalVoiceDiagnosticReport.shared.record("execution_started", "mechanism=eventkit")
                eventKitExecutionTask = Task { [weak self] in
                    guard let self else { return }
                    defer {
                        if activeRequestGeneration == requestGeneration {
                            eventKitExecutionInFlight = false
                            deliverCompletedDiagnosticSession()
                        }
                    }
                    do {
                        let result = try await eventKitExecutor.execute(command)
                        try Task.checkCancellation()
                        guard activeRequestGeneration == requestGeneration else { return }
                        resultState = .eventKit(result)
                        statusText = AppText.value("ready")
                        LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=eventkit")
                    } catch let error as EventKitExecutionError {
                        guard !Task.isCancelled, activeRequestGeneration == requestGeneration else { return }
                        LocalVoiceDiagnosticReport.shared.record("execution_failed", "mechanism=eventkit reason=\(String(describing: error)) error_type=EventKitExecutionError")
                        switch error {
                        case .unresolvedDateTime, .missingSubject, .ambiguousItem:
                            resultState = .clarification(summary)
                            statusText = AppText.value("clarification_needed")
                        default:
                            presentFailure(message: String(localized: "eventkit_unavailable"))
                        }
                    } catch {
                        guard !Task.isCancelled, activeRequestGeneration == requestGeneration else { return }
                        let failure = error as NSError
                        LocalVoiceDiagnosticReport.shared.record("execution_failed", "mechanism=eventkit reason=unavailable error_domain=\(failure.domain) error_code=\(failure.code) error_type=\(String(describing: type(of: error)))")
                        presentFailure(message: String(localized: "eventkit_unavailable"))
                    }
                }
                return
            }
            if command.intent == .audioRecord {
                let action = AudioRecorderCommand(rawValue: command.entities["recorder_action"] ?? "start") ?? .start
                resultState = .processing
                statusText = AppText.value("processing")
                capabilityExecutionInFlight = true
                Task { [weak self] in
                    guard let self else { return }
                    await recorder.execute(action)
                    if recorder.state == .failed || recorder.state == .denied {
                        presentFailure(message: AppText.value("request_unavailable"))
                        LocalVoiceDiagnosticReport.shared.record("execution_failed", "capability=audio_record")
                    } else {
                        resultState = .idle
                        statusText = AppText.value("ready")
                        if action == .stop, recorder.state == .stopped, let url = recorder.recordingURL {
                            currentContext.replaceShared(kind: .document, value: url.path)
                            capabilityPresentation = .audioFile(url)
                        }
                        LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=audio_record state=\(String(describing: recorder.state))")
                    }
                    capabilityExecutionInFlight = false
                    deliverCompletedDiagnosticSession()
                }
                return
            }
            if command.intent == .webSearch {
                presentGeneralInformation(command, summary: summary, requestGeneration: requestGeneration)
                return
            }
            if interactionDecision?.pattern == .confirmation {
                requireConfirmation(command, summary: summary, generation: requestGeneration)
                return
            }
            executeCanonicalCapability(command, summary: summary, requestGeneration: requestGeneration)
        }
    }

    private func presentGeneralInformation(
        _ command: StructuredCommand,
        summary: ResultSummary,
        requestGeneration: UInt64,
        browserFallbackAllowed: Bool = true
    ) {
        do {
            _ = try GenericIntentParser().parse(command.originalText)
        } catch GenericDiscoveryError.ambiguous {
            resultState = .clarification(summary)
            statusText = AppText.value("clarification_needed")
            LocalVoiceDiagnosticReport.shared.recordTerminal(.clarification)
            deliverCompletedDiagnosticSession()
            return
        } catch {
            presentFailure(message: AppText.value("request_unavailable"))
            LocalVoiceDiagnosticReport.shared.recordTerminal(.error)
            deliverCompletedDiagnosticSession()
            return
        }
        guard let genericDiscovery else {
            if browserFallbackAllowed {
                presentGeneralWebFallback(command)
            } else {
                presentExternalProviderRequirement(command)
            }
            deliverCompletedDiagnosticSession()
            return
        }
        resultState = .processing
        statusText = AppText.value("processing")
        LocalVoiceDiagnosticReport.shared.suspendForInteractiveContinuation("provider", generation: requestGeneration)
        genericDiscoveryTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if activeRequestGeneration == requestGeneration { deliverCompletedDiagnosticSession() }
            }
            LocalVoiceDiagnosticReport.shared.recordBoundaryPre("PROVIDER", "capability=general_information")
            do {
                let result = try await genericDiscovery.execute(text: command.originalText, parsed: command)
                try Task.checkCancellation()
                guard activeRequestGeneration == requestGeneration else { return }
                resumeInteractiveDiagnosticContinuation(generation: requestGeneration)
                LocalVoiceDiagnosticReport.shared.recordBoundaryPost("PROVIDER", "capability=general_information status=success")
                currentContext.replaceAnswer(result.primaryAnswer)
                resultState = .deterministic(result)
                statusText = AppText.value("ready")
                LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=deterministic_general_information")
            } catch GenericDiscoveryError.ambiguous {
                guard !Task.isCancelled, activeRequestGeneration == requestGeneration else { return }
                resumeInteractiveDiagnosticContinuation(generation: requestGeneration)
                LocalVoiceDiagnosticReport.shared.recordBoundaryPost("PROVIDER", "capability=general_information status=clarification")
                resultState = .clarification(summary)
                statusText = AppText.value("clarification_needed")
                LocalVoiceDiagnosticReport.shared.recordTerminal(.clarification)
            } catch {
                guard !Task.isCancelled, activeRequestGeneration == requestGeneration else { return }
                resumeInteractiveDiagnosticContinuation(generation: requestGeneration)
                LocalVoiceDiagnosticReport.shared.recordBoundaryPost("PROVIDER", "capability=general_information status=error")
                if browserFallbackAllowed {
                    presentGeneralWebFallback(command)
                } else {
                    presentExternalProviderRequirement(command)
                }
            }
        }
    }

    /// Browser fallback is a product decision, not a generic executor error
    /// handler. Preserve the two canonical informational domains that
    /// explicitly permit a deliberate web continuation, while keeping typed
    /// commerce, ride, booking and service requests at a truthful provider
    /// boundary when no structured provider is configured.
    private func externalProviderBrowserFallbackAllowed(for command: StructuredCommand) -> Bool {
        _ = command
        return false
    }

    private func presentExternalProviderRequirement(_ command: StructuredCommand) {
        LocalVoiceDiagnosticReport.shared.record(
            "generic_web_selected",
            "selected=false reason=typed_external_provider_boundary capability=\(command.intent.rawValue)"
        )
        LocalVoiceDiagnosticReport.shared.recordTerminal(.providerRequired)
        presentFailure(message: "Для цього запиту потрібен підключений провайдер")
    }

    private func presentGeneralWebFallback(_ command: StructuredCommand) {
        LocalVoiceDiagnosticReport.shared.record(
            "generic_web_selected",
            "selected=true reason=deliberate_provider_or_general_information_fallback"
        )
        do {
            let intent = try GenericIntentParser().parse(command.originalText)
            let minimized = try GenericQuerySanitizer().query(for: intent)
            let safe = StructuredCommand(originalText: minimized, normalizedText: minimized.lowercased(), language: command.language, intent: .unknown)
            let destination = try webSearchHandoff.destination(for: safe, structuredCapabilityAvailable: false)
            resultState = .webHandoff(.init(query: command.originalText, destination: destination))
            statusText = AppText.value("ready")
            LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=web_handoff_fallback")
        } catch {
            LocalVoiceDiagnosticReport.shared.record("execution_failed", "mechanism=web_handoff reason=invalid_safe_destination")
            LocalVoiceDiagnosticReport.shared.recordTerminal(.error)
            presentFailure(message: AppText.value("request_unavailable"))
        }
    }

    private func diagnosticSemanticFrameDetails(for command: StructuredCommand, constraintCount: Int) -> String {
        let observed = CanonicalSemanticFrameAnalyzer()
            .analyze(original: command.originalText, normalized: command.normalizedText)
            .frame
        let personPresent = observed.person != nil || command.entities["contact"] != nil || command.entities["recipient"] != nil
        let servicePresent = observed.service != nil || command.entities["call_service"] != nil || command.entities["message_service"] != nil
        let appPresent = observed.app != nil || command.entities["app"] != nil
        let destinationPresent = command.entities["destination"] != nil || observed.location != nil
        let locationRole: String
        if command.entities["near_current_location"] == "true" || observed.contextReference == .currentLocation {
            locationRole = "current"
        } else if command.entities["location"] != nil || observed.location != nil {
            locationRole = "specified"
        } else {
            locationRole = "none"
        }
        let datePresent = observed.temporal?.relativeDayOffset != nil || observed.temporal?.calendarDay != nil || command.entities["calendar_day"] != nil
        let timePresent = observed.temporal?.hour != nil || command.entities["hour"] != nil || command.entities["time"] != nil
        let durationPresent = observed.temporal?.durationSeconds != nil || observed.temporal?.relativeIntervalSeconds != nil || command.entities["duration_seconds"] != nil
        return [
            "action=\(observed.action?.rawValue ?? command.intent.rawValue)",
            "object=\(observed.object?.rawValue ?? "none")",
            "target=\(observed.object?.rawValue ?? "none")",
            "source=\(observed.source?.rawValue ?? "none")",
            "destination=\(destinationPresent ? "present" : "none")",
            "person=\(personPresent ? "present" : "none")",
            "service=\(servicePresent ? "resolved" : "none")",
            "app=\(appPresent ? "resolved" : "none")",
            "location=\(locationRole)",
            "date=\(datePresent ? "present" : "none")",
            "time=\(timePresent ? "present" : "none")",
            "duration=\(durationPresent ? "present" : "none")",
            "constraints=\(constraintCount)",
            "constraint_count=\(constraintCount)",
            "confidence=\(String(format: "%.3f", observed.confidence))"
        ].joined(separator: " ")
    }

    private static func diagnosticCandidateFingerprints(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "none" }
        let alphabet = Array("abcdefghijklmnop")
        return raw.split(separator: "|").prefix(3).map { candidate in
            SHA256.hash(data: Data(candidate.utf8)).prefix(6).flatMap { byte in
                [alphabet[Int(byte >> 4)], alphabet[Int(byte & 0x0f)]]
            }.map(String.init).joined()
        }.joined(separator: "|")
    }

    private func openSystemHandoffObserved(_ destination: URL) {
        let scheme = destination.scheme?.lowercased()
        let boundary = scheme == "tel" ? "CALL_URL" : nil
        if let boundary {
            LocalVoiceDiagnosticReport.shared.recordBoundaryPre(boundary, "scheme=tel")
        }
        systemHandoffOpen(destination)
        if let boundary {
            LocalVoiceDiagnosticReport.shared.recordBoundaryPost(boundary, "scheme=tel status=dispatched")
        }
    }

    private func executeCanonicalCapability(_ command: StructuredCommand, summary: ResultSummary, requestGeneration: UInt64) {
        resultState = .processing
        statusText = AppText.value("processing")
        capabilityExecutionInFlight = true
        capabilityExecutionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if activeRequestGeneration == requestGeneration {
                    capabilityExecutionInFlight = false
                    deliverCompletedDiagnosticSession()
                }
            }
            LocalVoiceDiagnosticReport.shared.record("permission_state", "capability=\(command.intent.rawValue) status=delegated")
            LocalVoiceDiagnosticReport.shared.recordBoundaryPre("EXECUTOR", "capability=\(command.intent.rawValue)")
            do {
                let outcome = try await capabilityExecutor.execute(command)
                LocalVoiceDiagnosticReport.shared.recordBoundaryPost("EXECUTOR", "capability=\(command.intent.rawValue) status=success")
                try Task.checkCancellation()
                guard activeRequestGeneration == requestGeneration else { return }
                LocalVoiceDiagnosticReport.shared.recordBoundaryPre("RENDERER_ACTION", "capability=\(command.intent.rawValue)")
                switch outcome {
                case let .result(result):
                    currentContext.replaceAnswer(result.primaryAnswer)
                    resultState = .deterministic(result)
                    LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=deterministic capability=\(command.intent.rawValue)")
                case let .handoff(result):
                    if result.kind == .system {
                        openSystemHandoffObserved(result.destination)
                        resultState = .idle
                    } else {
                        resultState = .webHandoff(result)
                    }
                    LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=handoff capability=\(command.intent.rawValue)")
                case let .presentation(presentation):
                    LocalVoiceDiagnosticReport.shared.suspendForInteractiveContinuation(presentation.id)
                    capabilityPresentation = presentation
                    capabilityPresentationGeneration = presentation.id == "contact-access" ? requestGeneration : nil
                    capabilityPresentationCommandID = presentation.id == "contact-access" ? command.id : nil
                    resultState = .idle
                    LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=system_presentation capability=\(command.intent.rawValue)")
                case let .suspended(presentation, continuation):
                    LocalVoiceDiagnosticReport.shared.suspendForInteractiveContinuation(presentation.id)
                    capabilityContinuation = continuation
                    capabilityPresentation = presentation
                    resultState = .idle
                    LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=compound_presentation capability=\(command.intent.rawValue)")
                }
                statusText = AppText.value("ready")
                LocalVoiceDiagnosticReport.shared.recordBoundaryPost("RENDERER_ACTION", "capability=\(command.intent.rawValue) status=success")
            } catch is CancellationError {
                LocalVoiceDiagnosticReport.shared.recordBoundaryPost("EXECUTOR", "capability=\(command.intent.rawValue) status=cancelled")
                LocalVoiceDiagnosticReport.shared.recordTerminal(.cancelled)
                return
            } catch let CanonicalCapabilityExecutionError.ambiguous(values) {
                LocalVoiceDiagnosticReport.shared.recordBoundaryPost("EXECUTOR", "capability=\(command.intent.rawValue) status=error")
                guard activeRequestGeneration == requestGeneration else { return }
                let choices = Array(values.prefix(3))
                pendingCanonicalSelection = (
                    command, summary, requestGeneration,
                    Self.selectionRole(for: command, choices: choices), choices
                )
                LocalVoiceDiagnosticReport.shared.suspendForInteractiveContinuation("canonical-clarification", generation: requestGeneration)
                requireAction(prompt: AppText.value("clarification_needed"), choices: choices)
                statusText = AppText.value("clarification_needed")
            } catch let CanonicalCapabilityExecutionError.missingParameter(parameter) {
                LocalVoiceDiagnosticReport.shared.recordBoundaryPost("EXECUTOR", "capability=\(command.intent.rawValue) status=error")
                guard activeRequestGeneration == requestGeneration else { return }
                LocalVoiceDiagnosticReport.shared.record("router_rejected", "reason=missing_parameter parameter=\(parameter)")
                resultState = .clarification(summary)
                statusText = AppText.value("clarification_needed")
                LocalVoiceDiagnosticReport.shared.recordTerminal(.clarification)
            } catch let CanonicalCapabilityExecutionError.confirmationRequired(preparedCommand) {
                LocalVoiceDiagnosticReport.shared.recordBoundaryPost("EXECUTOR", "capability=\(command.intent.rawValue) status=confirmation_required")
                guard activeRequestGeneration == requestGeneration else { return }
                requireConfirmation(
                    preparedCommand,
                    summary: .init(request: command.originalText, intent: command.intent, risk: .consequential),
                    generation: requestGeneration
                )
            } catch let CanonicalCapabilityExecutionError.providerRequiredNoFallback(providerClass) {
                LocalVoiceDiagnosticReport.shared.recordBoundaryPost("EXECUTOR", "capability=\(command.intent.rawValue) status=provider_required")
                guard activeRequestGeneration == requestGeneration else { return }
                LocalVoiceDiagnosticReport.shared.record("execution_failed", "reason=provider_required_no_web_fallback capability=\(providerClass)")
                presentFailure(message: "Потрібен підключений провайдер бронювання")
                LocalVoiceDiagnosticReport.shared.recordTerminal(.providerRequired)
            } catch let CanonicalCapabilityExecutionError.externalProviderRequired(providerClass) {
                LocalVoiceDiagnosticReport.shared.recordBoundaryPost("EXECUTOR", "capability=\(command.intent.rawValue) status=provider_required")
                guard activeRequestGeneration == requestGeneration else { return }
                LocalVoiceDiagnosticReport.shared.record("execution_failed", "reason=external_provider_required capability=\(providerClass)")
                presentGeneralInformation(
                    command,
                    summary: summary,
                    requestGeneration: requestGeneration,
                    browserFallbackAllowed: externalProviderBrowserFallbackAllowed(for: command)
                )
            } catch let CanonicalCapabilityExecutionError.unavailable(reason) {
                LocalVoiceDiagnosticReport.shared.recordBoundaryPost("EXECUTOR", "capability=\(command.intent.rawValue) status=error")
                guard activeRequestGeneration == requestGeneration else { return }
                LocalVoiceDiagnosticReport.shared.record("execution_failed", "reason=capability_unavailable capability=\(command.intent.rawValue) detail=\(reason)")
                presentFailure(message: AppText.value("request_unavailable"))
            } catch {
                LocalVoiceDiagnosticReport.shared.recordBoundaryPost("EXECUTOR", "capability=\(command.intent.rawValue) status=error")
                guard activeRequestGeneration == requestGeneration else { return }
                LocalVoiceDiagnosticReport.shared.record("execution_failed", "reason=capability_unavailable capability=\(command.intent.rawValue)")
                presentFailure(message: AppText.value("request_unavailable"))
            }
        }
    }

    private func resumeInteractiveDiagnosticContinuation(generation: UInt64? = nil) {
        LocalVoiceDiagnosticReport.shared.resumeInteractiveContinuation(generation: generation)
    }

    private func completeInteractiveDiagnosticContinuation(_ state: DiagnosticTerminalState, details: String = "") {
        if LocalVoiceDiagnosticReport.shared.finishInteractiveContinuation(state, details: details) {
            deliverCompletedDiagnosticSession()
        }
    }

    private func deliverCompletedDiagnosticSession() {
        if let session = LocalVoiceDiagnosticReport.shared.completedSession() {
            Task { await PhysicalDiagnosticDelivery.shared.enqueue(session) }
        }
    }

    func handleScannedCode(_ observation: ObservedScannerCode) {
        capabilityPresentation = nil
        do {
            resultState = .scanner(try ScannerProductionRouter().route(observation))
            statusText = AppText.value("ready")
            LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=scanner type=\(observation.isQR ? "qr" : "barcode")")
            completeInteractiveDiagnosticContinuation(.success, details: "kind=scanner")
        } catch {
            presentFailure(message: AppText.value("request_unavailable"))
            completeInteractiveDiagnosticContinuation(.error, details: "kind=scanner")
        }
    }

    func handleScannerUnavailable() {
        capabilityPresentation = nil
        presentFailure(message: AppText.value("request_unavailable"))
        completeInteractiveDiagnosticContinuation(.unsupported, details: "kind=scanner")
    }

    func performScannerAction(_ result: ScannerProductionResult) {
        switch result.route.content {
        case let .url(url) where result.route.action == .open: UIApplication.shared.open(url)
        case let .text(value) where result.route.action == .save: UIPasteboard.general.string = value; statusText = AppText.value("ready")
        case let .text(value) where result.route.action == .call:
            let number = value.replacingOccurrences(of: "tel:", with: ""); if let url = URL(string: "tel:\(number.filter(\.isNumber))") { UIApplication.shared.open(url) }
        case let .vCard(data) where result.route.action == .importContact: capabilityPresentation = .contactImport(data)
        case let .retailBarcode(value):
            let command = StructuredCommand(originalText: "GTIN \(value)", normalizedText: "gtin \(value)", language: .automatic, intent: .productSearch, entities: ["query": "GTIN \(value)"])
            presentExternalProviderRequirement(command)
        default: presentFailure(message: AppText.value("request_unavailable"))
        }
    }
    func performResultAction(_ action: ResultAction) {
        guard action.kind == .showPhoto, action.id.hasPrefix("photos:") else { return }
        capabilityPresentation = .photoAsset(String(action.id.dropFirst("photos:".count)))
    }

    func handleCapturedOCRImage(_ image: UIImage?) { processOCR(image, provenance: .camera) }
    func handleSelectedPhotoLibraryAsset(_ identifier: String?) {
        guard let identifier, !identifier.isEmpty else {
            dismissCapabilityPresentation()
            return
        }
        capabilityPresentation = .photoAsset(identifier)
        LocalVoiceDiagnosticReport.shared.recordBoundaryPost(
            "PHOTOKIT", "operation=library_selection status=selected"
        )
    }
    func handlePhotoOCRImage(_ image: UIImage?) { processOCR(image, provenance: .photoLibrary) }
    func handleSelectedOCRDocuments(_ urls: [URL]) {
        capabilityPresentation = nil
        guard let url = urls.first else {
            presentFailure(message: AppText.value("request_unavailable"))
            completeInteractiveDiagnosticContinuation(.noResult, details: "kind=document_picker")
            return
        }
        let accessed = url.startAccessingSecurityScopedResource()
        let image = UIImage(contentsOfFile: url.path)
        if accessed { url.stopAccessingSecurityScopedResource() }
        processOCR(image, provenance: .document)
    }
    func handleSelectedPDFDocuments(_ urls: [URL], operation: PDFWorkflowOperation, text: String?) {
        capabilityPresentation = nil
        guard !urls.isEmpty else {
            presentFailure(message: AppText.value("request_unavailable"))
            completeInteractiveDiagnosticContinuation(.noResult, details: "kind=pdf_picker")
            return
        }
        resumeInteractiveDiagnosticContinuation(generation: activeRequestGeneration)
        do {
            let data = try urls.map { url -> Data in
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                return try Data(contentsOf: url)
            }
            let processor = OnDevicePDFProcessor()
            if operation == .read {
                LocalVoiceDiagnosticReport.shared.suspendForInteractiveContinuation("document-file")
                capabilityPresentation = .documentFile(urls[0])
                return
            }
            let outputs: [Data]
            switch operation {
            case .merge: outputs = [try processor.merge(data)]
            case .split:
                let count = try processor.pageCount(data[0])
                outputs = try processor.split(data[0], groups: (0..<count).map { [$0] })
            case .rotate:
                let count = try processor.pageCount(data[0])
                outputs = [try processor.rotating(Set(0..<count), degreesClockwise: 90, in: data[0])]
            case .compress: outputs = [try processor.compressed(data[0])]
            case .highlight:
                guard let text, !text.isEmpty else { throw PDFProcessingError.invalidPageSelection }
                outputs = [try processor.highlighting(text, in: data[0])]
            case .redact:
                guard let text, !text.isEmpty else { throw CanonicalCapabilityExecutionError.missingParameter("pdf_redaction_text") }
                outputs = [try processor.redacting(text, in: data[0])]
            case .read: outputs = []
            }
            let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appending(path: "UniversalAssistant/PDF", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            let outputURLs = try outputs.enumerated().map { index, output in
                let url = base.appending(path: "PDF-Result-\(UUID().uuidString)-\(index + 1).pdf")
                try output.write(to: url, options: .atomic); return url
            }
            guard !outputURLs.isEmpty else { throw PDFProcessingError.emptyDocument }
            currentContext.replaceShared(kind: .document, value: outputURLs[0].path)
            let presentation: CapabilityPresentation = outputURLs.count == 1 ? .documentFile(outputURLs[0]) : .documentFiles(outputURLs)
            LocalVoiceDiagnosticReport.shared.suspendForInteractiveContinuation(presentation.id)
            capabilityPresentation = presentation
            resultState = .idle; statusText = AppText.value("ready")
        } catch {
            presentFailure(message: AppText.value("request_unavailable"))
            LocalVoiceDiagnosticReport.shared.recordTerminal(.error)
            deliverCompletedDiagnosticSession()
        }
    }
    func handleScannedOCRDocument(_ pages: [UIImage]) { handleScannedDocument(pages, mode: .recognizedText) }
    func handleScannedDocument(_ pages: [UIImage], mode: DocumentScanOutputMode) {
        capabilityPresentation = nil
        guard !pages.isEmpty else {
            presentFailure(message: AppText.value("request_unavailable"))
            completeInteractiveDiagnosticContinuation(.noResult, details: "kind=document_scan")
            return
        }
        activeRequestGeneration &+= 1
        let requestGeneration = activeRequestGeneration
        resumeInteractiveDiagnosticContinuation(generation: requestGeneration)
        ocrExecutionTask?.cancel()
        resultState = .processing
        ocrExecutionTask = Task { [weak self] in
            guard let self else { return }
            LocalVoiceDiagnosticReport.shared.recordBoundaryPre("OCR", "source=document pages=\(pages.count)")
            defer {
                LocalVoiceDiagnosticReport.shared.recordBoundaryPost("OCR", "source=document status=returned")
                if activeRequestGeneration == requestGeneration { deliverCompletedDiagnosticSession() }
            }
            do {
                if mode == .pdf {
                    var recognized: [String] = []
                    for image in pages {
                        recognized.append((try? await ocrPipeline.process(image, provenance: .document).recognizedText) ?? "")
                    }
                    let data = try OnDevicePDFProcessor().searchablePDF(images: pages, recognizedText: recognized)
                    let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                        .appending(path: "UniversalAssistant/Scans", directoryHint: .isDirectory)
                    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
                    let url = base.appending(path: "Scan-\(UUID().uuidString).pdf")
                    try data.write(to: url, options: .atomic)
                    guard !Task.isCancelled, activeRequestGeneration == requestGeneration else { return }
                    currentContext.replaceShared(kind: .document, value: url.path)
                    LocalVoiceDiagnosticReport.shared.suspendForInteractiveContinuation("document-file", generation: requestGeneration)
                    capabilityPresentation = .documentFile(url)
                    resultState = .idle; statusText = AppText.value("ready")
                    LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=document_pdf pages=\(pages.count)")
                    return
                }
                let result = try await ocrPipeline.process(pages, provenance: .document)
                guard !Task.isCancelled, activeRequestGeneration == requestGeneration else { return }
                resultState = .ocr(result); statusText = AppText.value("ready")
                resumeCapabilityContinuation(with: .recognizedText(result.recognizedText))
                LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=ocr source=document pages=\(pages.count)")
            } catch {
                guard !Task.isCancelled, activeRequestGeneration == requestGeneration else { return }
                presentFailure(message: AppText.value("request_unavailable"))
            }
        }
    }
    func handleDocumentScannerFailure(_ error: Error) {
        capabilityPresentation = nil
        presentFailure(message: AppText.value("request_unavailable"))
        completeInteractiveDiagnosticContinuation(.error, details: "kind=document_scan")
    }
    private func processOCR(_ image: UIImage?, provenance: OCRInputProvenance) {
        capabilityPresentation = nil
        guard image != nil else {
            presentFailure(message: AppText.value("request_unavailable"))
            completeInteractiveDiagnosticContinuation(.noResult, details: "kind=ocr_input")
            return
        }
        activeRequestGeneration &+= 1
        let requestGeneration = activeRequestGeneration
        resumeInteractiveDiagnosticContinuation(generation: requestGeneration)
        ocrExecutionTask?.cancel()
        resultState = .processing
        ocrExecutionTask = Task { [weak self] in
            guard let self else { return }
            LocalVoiceDiagnosticReport.shared.recordBoundaryPre("OCR", "source=\(provenance.rawValue)")
            defer {
                LocalVoiceDiagnosticReport.shared.recordBoundaryPost("OCR", "source=\(provenance.rawValue) status=returned")
                if activeRequestGeneration == requestGeneration { deliverCompletedDiagnosticSession() }
            }
            do {
                let result = try await ocrPipeline.process(image, provenance: provenance)
                guard !Task.isCancelled, activeRequestGeneration == requestGeneration else { return }
                resultState = .ocr(result); statusText = AppText.value("ready")
                resumeCapabilityContinuation(with: .recognizedText(result.recognizedText))
                LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=ocr source=\(provenance.rawValue)")
            } catch {
                guard !Task.isCancelled, activeRequestGeneration == requestGeneration else { return }
                presentFailure(message: AppText.value("request_unavailable"))
            }
        }
    }

    private func resumeCapabilityContinuation(with output: CanonicalDependencyOutput) {
        guard let continuation = capabilityContinuation else { return }
        capabilityContinuation = nil
        activeRequestGeneration &+= 1
        let generation = activeRequestGeneration
        LocalVoiceDiagnosticReport.shared.record(
            "dependency_output_type",
            "output_type=\(output.diagnosticTypeName) generation=\(generation)"
        )
        LocalVoiceDiagnosticReport.shared.suspendForInteractiveContinuation("compound_dependency", generation: generation)
        capabilityExecutionTask?.cancel()
        capabilityExecutionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if activeRequestGeneration == generation { deliverCompletedDiagnosticSession() }
            }
            do {
                let outcome = try await capabilityExecutor.resume(continuation, with: output)
                guard !Task.isCancelled, activeRequestGeneration == generation else { return }
                resumeInteractiveDiagnosticContinuation(generation: generation)
                switch outcome {
                case let .result(value):
                    resultState = .deterministic(value)
                    LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=compound_result")
                case let .handoff(value):
                    if value.kind == .system || value.kind == .navigation {
                        openSystemHandoffObserved(value.destination)
                        resultState = .idle
                    } else {
                        resultState = .webHandoff(value)
                    }
                    LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=compound_handoff")
                case let .presentation(value):
                    LocalVoiceDiagnosticReport.shared.suspendForInteractiveContinuation(value.id)
                    capabilityPresentation = value; resultState = .idle
                case let .suspended(value, next):
                    LocalVoiceDiagnosticReport.shared.suspendForInteractiveContinuation(value.id)
                    capabilityContinuation = next; capabilityPresentation = value; resultState = .idle
                }
                statusText = AppText.value("ready")
            } catch {
                guard !Task.isCancelled, activeRequestGeneration == generation else { return }
                resumeInteractiveDiagnosticContinuation(generation: generation)
                LocalVoiceDiagnosticReport.shared.record("execution_failed", "mechanism=compound_resume reason=execution_error")
                LocalVoiceDiagnosticReport.shared.recordTerminal(.error)
                presentFailure(message: AppText.value("request_unavailable"))
            }
        }
    }
    func performOCRAction(_ result: OCRProductionResult, _ action: OCRResultAction) {
        switch action {
        case .copy: UIPasteboard.general.string = result.recognizedText; statusText = AppText.value("ready")
        case .share: capabilityPresentation = .share(result.recognizedText)
        case .translate:
            input = result.recognizedText
            requireAction(prompt: "Оберіть мову перекладу", choices: ["Українська", "English", "Deutsch"])
            capabilityPresentation = .translationTarget(result.recognizedText)
        }
    }
    func startTranslation(_ text: String, _ targetLanguage: String) {
        resumeInteractiveDiagnosticContinuation()
        do {
            let plan = try CameraIntelligenceCore().translationPlan(text: text, sourceLanguage: TranslationSourceLanguageResolver().resolve(text), targetLanguage: targetLanguage)
            LocalVoiceDiagnosticReport.shared.suspendForInteractiveContinuation("translation")
            capabilityPresentation = .translation(plan)
        } catch {
            capabilityPresentation = nil
            presentFailure(message: AppText.value("request_unavailable"))
            LocalVoiceDiagnosticReport.shared.recordTerminal(.error)
            deliverCompletedDiagnosticSession()
        }
    }
    func handleTranslationResult(_ result: TranslationProductionResult) {
        currentContext.replaceTranslation(sourceText: result.sourceText, sourceLanguage: result.sourceLanguage)
        capabilityPresentation = nil
        resultState = .translation(result)
        statusText = AppText.value("ready")
        LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=translation")
        completeInteractiveDiagnosticContinuation(.success, details: "kind=translation")
    }
    func handleTranslationFailure() {
        capabilityPresentation = nil
        presentFailure(message: AppText.value("request_unavailable"))
        completeInteractiveDiagnosticContinuation(.error, details: "kind=translation")
    }
    func performTranslationAction(_ result: TranslationProductionResult, _ action: OCRResultAction) {
        switch action { case .copy: UIPasteboard.general.string = result.translatedText; case .share: capabilityPresentation = .share(result.translatedText); case .translate: break }
    }
    func handleContactAccessGranted(_ identifiers: [String], for command: StructuredCommand) {
        guard capabilityPresentationGeneration == activeRequestGeneration, capabilityPresentationCommandID == command.id else {
            capabilityPresentation = nil
            capabilityPresentationGeneration = nil
            capabilityPresentationCommandID = nil
            return
        }
        capabilityPresentation = nil
        capabilityPresentationGeneration = nil
        capabilityPresentationCommandID = nil
        guard !identifiers.isEmpty else {
            presentFailure(message: AppText.value("request_unavailable"))
            completeInteractiveDiagnosticContinuation(.noResult, details: "kind=contact_access")
            return
        }
        activeRequestGeneration &+= 1
        let generation = activeRequestGeneration
        resumeInteractiveDiagnosticContinuation(generation: generation)
        var entities = command.entities
        if identifiers.count == 1, let identifier = identifiers.first { entities["contact_identifier"] = identifier }
        let resumed = StructuredCommand(id: command.id, originalText: command.originalText, normalizedText: command.normalizedText, language: command.language, intent: command.intent, entities: entities, constraints: command.constraints, risk: command.risk, needsClarification: false)
        executeCanonicalCapability(resumed, summary: .init(request: command.originalText, intent: command.intent, risk: command.risk), requestGeneration: generation)
    }

    func dismissCapabilityPresentation() {
        capabilityPresentation = nil
        capabilityPresentationGeneration = nil
        capabilityPresentationCommandID = nil
        capabilityContinuation = nil
        completeInteractiveDiagnosticContinuation(.cancelled, details: "reason=user_dismissed")
    }

    func beginProcessing() {
        resultDismissTask?.cancel()
        resultState = .processing
        statusText = AppText.value("processing")
    }

    private func requireConfirmation(_ command: StructuredCommand, summary: ResultSummary, generation: UInt64) {
        pendingConfirmation = (command, summary, generation)
        requireAction(prompt: AppText.value("confirmation_required"), choices: [AppText.value("confirm"), AppText.value("cancel")])
        LocalVoiceDiagnosticReport.shared.record("router_rejected", "reason=confirmation_required")
    }

    func resolveActionRequiredChoice(_ choice: String) {
        if let pending = pendingCanonicalSelection,
           pending.generation == activeRequestGeneration,
           pending.choices.contains(choice) {
            pendingCanonicalSelection = nil
            let resumed = Self.command(pending.command, selecting: choice, role: pending.role)
            resumeInteractiveDiagnosticContinuation(generation: pending.generation)
            LocalVoiceDiagnosticReport.shared.record(
                "clarification_resolved",
                "role=\(pending.role) capability=\(pending.command.intent.rawValue)"
            )
            executeCanonicalCapability(resumed, summary: pending.summary, requestGeneration: pending.generation)
            return
        }
        guard let pending = pendingConfirmation, pending.generation == activeRequestGeneration else { return }
        let confirmed = choice == AppText.value("confirm")
        pendingConfirmation = nil
        guard confirmed else {
            resultState = .idle
            statusText = AppText.value("ready")
            LocalVoiceDiagnosticReport.shared.record("confirmation_resolved", "accepted=false")
            LocalVoiceDiagnosticReport.shared.recordTerminal(.cancelled)
            deliverCompletedDiagnosticSession()
            return
        }
        LocalVoiceDiagnosticReport.shared.record("confirmation_resolved", "accepted=true capability=\(pending.command.intent.rawValue)")
        let isRestaurantCancellation = pending.command.intent == .cancel &&
            pending.command.entities["reservation_operation"] == "cancel"
        if pending.command.intent == .calendarDelete || (pending.command.intent == .cancel && !isRestaurantCancellation) {
            executeConfirmedEventKit(pending.command, generation: pending.generation)
        } else {
            executeCanonicalCapability(pending.command, summary: pending.summary, requestGeneration: pending.generation)
        }
    }

    private func executeConfirmedEventKit(_ command: StructuredCommand, generation: UInt64) {
        eventKitExecutionInFlight = true
        resultState = .processing
        statusText = AppText.value("processing")
        eventKitExecutionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if activeRequestGeneration == generation {
                    eventKitExecutionInFlight = false
                    deliverCompletedDiagnosticSession()
                }
            }
            do {
                let value = try await eventKitExecutor.execute(command)
                try Task.checkCancellation()
                guard activeRequestGeneration == generation else { return }
                resultState = .eventKit(value)
                statusText = AppText.value("ready")
                LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=eventkit confirmed=true")
            } catch {
                guard !Task.isCancelled, activeRequestGeneration == generation else { return }
                presentFailure(message: String(localized: "eventkit_unavailable"))
            }
        }
    }

    private static func selectionRole(for command: StructuredCommand, choices: [String]) -> String {
        switch command.intent {
        case .open, .appAction:
            return "application"
        case .contactLookup, .contactCall:
            let arePhoneNumbers = !choices.isEmpty && choices.allSatisfy { $0.filter(\.isNumber).count >= 7 }
            return arePhoneNumbers ? "phone_number" : "contact"
        case .messageCompose:
            return "recipient"
        default:
            return "subject"
        }
    }

    private static func command(_ command: StructuredCommand, selecting choice: String, role: String) -> StructuredCommand {
        var entities = command.entities
        var selectedIntent = command.intent
        entities.removeValue(forKey: "clarification_options")
        entities.removeValue(forKey: "clarification_role")
        switch role {
        case "application":
            entities["app"] = choice
        case "service_channel":
            if command.intent == .contactCall { entities["call_service"] = choice.lowercased() }
            else { entities["message_service"] = choice.lowercased() }
        case "phone_number":
            if command.intent == .messageCompose { entities["recipient"] = choice }
            else { entities["phone_number"] = choice }
        case "contact":
            if command.intent == .messageCompose { entities["recipient"] = choice }
            else { entities["contact"] = choice }
        case "recipient":
            entities["recipient"] = choice
        case "catalog":
            entities["query"] = choice
        case "vehicle_service":
            if choice == "Таксі" {
                selectedIntent = .taxiSearch
                entities["provider_domain"] = "ride_service"
                entities.removeValue(forKey: "serviceCategory")
            } else {
                selectedIntent = .serviceSearch
                entities["provider_domain"] = "car_rental"
                entities["serviceCategory"] = LocalServiceCategory.carRental.rawValue
            }
        default:
            entities["subject"] = choice
        }
        return .init(
            id: command.id,
            originalText: command.originalText,
            normalizedText: command.normalizedText,
            language: command.language,
            intent: selectedIntent,
            entities: entities,
            constraints: command.constraints,
            risk: command.risk,
            needsClarification: false
        )
    }

    func requireAction(prompt: String, choices: [String]) {
        resultDismissTask?.cancel()
        resultState = .actionRequired(.init(prompt: prompt, choices: choices))
    }

    func presentFailure(message: String, recoveryAction: String? = nil) {
        resultDismissTask?.cancel()
        statusText = message
        resultState = .failure(.init(message: message, recoveryAction: recoveryAction))
    }

    func presentExpanded(_ summary: ResultSummary) {
        resultDismissTask?.cancel()
        resultState = .expanded(summary)
    }

    func ingestShared(_ envelope: SharedInboxEnvelope) {
        guard let kind = ContextSharedContent.Kind(rawValue: envelope.kind) else { return }
        currentContext.replaceShared(kind: kind, value: envelope.value, observedAt: envelope.receivedAt)
        switch envelope.kind {
        case "url":
            guard let url = URL(string: envelope.value), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { presentFailure(message: AppText.value("request_unavailable")); return }
            resultState = .webHandoff(.init(query: url.host ?? envelope.value, destination: url, kind: .system))
            statusText = AppText.value("ready")
            return
        case "text":
            input = envelope.value
        case "vcard":
            input = "Використай переданий контакт"
        case "image":
            resultState = .idle
            statusText = AppText.value("ready")
            return
        case "document":
            input = "Опрацюй переданий документ"
        default:
            return
        }
        submit()
    }

    @discardableResult
    func ingestPendingShare(from store: SharedInboxStore = SharedInboxStore()) -> Bool {
        guard let envelope = store.consume() else { return false }
        ingestShared(envelope)
        return true
    }

    private func translationFollowUpTarget(_ text: String) -> String? {
        let value = text.lowercased()
        guard ["а тепер", "тепер", "now in", "and now"].contains(where: value.contains) else { return nil }
        if value.contains("німець") || value.contains("german") || value.contains("deutsch") { return "de" }
        if value.contains("англі") || value.contains("english") { return "en" }
        if value.contains("україн") || value.contains("ukrainian") { return "uk" }
        return nil
    }

    private func isSharedImageTextRequest(_ text: String) -> Bool {
        let value = text.lowercased()
        let frame = CanonicalSemanticFrameAnalyzer().analyze(original: text, normalized: value)
        return frame.frame.contextReference == .sharedContent &&
            (frame.frame.action == .recognize || frame.frame.object == .text)
    }

    private func isSharedURLOpenRequest(_ text: String) -> Bool {
        let value = text.lowercased()
        return ["відкрий це", "відкрий посилання", "open it", "open this link"].contains(where: value.contains)
    }

    @discardableResult
    func reportWrongResult() async -> UserFeedbackRecord? {
        guard resultState != .idle else { return nil }
        guard let record = try? await feedbackStore.record(.wrongResult) else { return nil }
        statusText = String(format: AppText.feedback("feedback_recorded_format"), record.diagnosticID)
        return record
    }
}
