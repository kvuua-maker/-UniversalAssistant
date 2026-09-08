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

    init(
        commandEngine: any CommandParsing = LocalCommandEngine(),
        interactionEngine: any InteractionDeciding = InteractionDecisionEngine(),
        weatherExecutor: any WeatherCommandExecuting = ProductionWeatherCommandExecutor(),
        webSearchHandoff: ControlledWebSearchHandoff = ControlledWebSearchHandoff(),
        genericDiscovery: GenericUnknownRequestCoordinator? = nil,
        eventKitExecutor: any EventKitCommandExecuting = ProductionEventKitCommandExecutor(),
        capabilityExecutor: (any CanonicalCapabilityExecuting)? = nil,
        ocrProcessor: (any DocumentOCRProcessing)? = nil,
        recorder: AudioRecorderController = AudioRecorderController(),
        feedbackStore: UserFeedbackStore = .shared,
        compactResultDuration: Duration = .seconds(2),
        presentationPreferenceStore: PresentationPreferenceStore = PresentationPreferenceStore(),
        voiceInput: VoiceInputController = VoiceInputController(),
        systemHandoffOpen: @escaping @MainActor (URL) -> Void = { UIApplication.shared.open($0) }
    ) {
        self.commandEngine = commandEngine
        self.interactionEngine = interactionEngine
        self.weatherExecutor = weatherExecutor
        self.webSearchHandoff = webSearchHandoff
        self.genericDiscovery = genericDiscovery
        self.eventKitExecutor = eventKitExecutor
        let currentContext = CurrentContextStore()
        self.currentContext = currentContext
        self.capabilityExecutor = capabilityExecutor ?? ProductionCanonicalCapabilityExecutor(currentContext: currentContext, recorder: recorder)
        self.ocrPipeline = OCRProductionPipeline(processor: ocrProcessor ?? OnDeviceDocumentOCR())
        self.recorder = recorder
        self.feedbackStore = feedbackStore
        self.compactResultDuration = compactResultDuration
        self.presentationPreferenceStore = presentationPreferenceStore
        self.voiceInput = voiceInput
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
            if state == .idle, !weatherExecutionInFlight, !eventKitExecutionInFlight, !capabilityExecutionInFlight, let session = LocalVoiceDiagnosticReport.shared.completedSession() {
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
        recorder.finalizeForLifecycleTransition()
        voiceInput.stop(reason: .sceneInactive)
        isListening = false
        resultDismissTask?.cancel()
    }

    func submit() {
        resultDismissTask?.cancel()
        activeRequestGeneration &+= 1
        let requestGeneration = activeRequestGeneration
        capabilityExecutionTask?.cancel()
        ocrExecutionTask?.cancel()
        weatherExecutionTask?.cancel()
        eventKitExecutionTask?.cancel()
        genericDiscoveryTask?.cancel()
        // A newly submitted command supersedes any UI-bound compound continuation.
        // Late scanner/OCR callbacks therefore cannot resume an obsolete plan.
        capabilityContinuation = nil
        weatherExecutionInFlight = false
        eventKitExecutionInFlight = false
        capabilityExecutionInFlight = false
        let submittedInput = input
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
            capabilityPresentation = .photoAsset(identifier)
            return
        }
        if isSharedURLOpenRequest(submittedInput), let shared = currentContext.freshShared(), shared.kind == .url,
           let url = URL(string: shared.value) {
            input = ""
            resultState = .webHandoff(.init(query: url.host ?? shared.value, destination: url, kind: .system))
            statusText = AppText.value("ready")
            return
        }
        let command = commandEngine.parse(submittedInput)
        LocalVoiceDiagnosticReport.shared.record(
            "router_received",
            "capability=\(command.intent.rawValue) language=\(command.language.rawValue)"
        )
        let summary = ResultSummary(request: command.originalText, intent: command.intent, risk: command.risk)
        interactionDecision = interactionEngine.decide(for: command)
        input = ""
        if command.needsClarification, command.intent == .unknown {
            presentGeneralInformation(command, summary: summary, requestGeneration: requestGeneration)
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
                    requireAction(prompt: AppText.value("confirmation_required"), choices: [AppText.value("confirm"), AppText.value("cancel")])
                    LocalVoiceDiagnosticReport.shared.record("router_rejected", "reason=confirmation_required")
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
            if command.intent == .webSearch || command.intent == .unknown {
                presentGeneralInformation(command, summary: summary, requestGeneration: requestGeneration)
                return
            }
            if interactionDecision?.pattern == .confirmation {
                requireAction(prompt: AppText.value("confirmation_required"), choices: [AppText.value("confirm"), AppText.value("cancel")])
                LocalVoiceDiagnosticReport.shared.record("router_rejected", "reason=confirmation_required")
                return
            }
            executeCanonicalCapability(command, summary: summary, requestGeneration: requestGeneration)
        }
    }

    private func presentGeneralInformation(_ command: StructuredCommand, summary: ResultSummary, requestGeneration: UInt64) {
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
        genericDiscoveryTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await genericDiscovery.execute(text: command.originalText, parsed: command)
                try Task.checkCancellation()
                guard activeRequestGeneration == requestGeneration else { return }
                currentContext.replaceAnswer(result.primaryAnswer)
                resultState = .deterministic(result)
                statusText = AppText.value("ready")
                LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=deterministic_general_information")
            } catch GenericDiscoveryError.ambiguous {
                guard !Task.isCancelled, activeRequestGeneration == requestGeneration else { return }
                resultState = .clarification(summary)
                statusText = AppText.value("clarification_needed")
            } catch {
                guard !Task.isCancelled, activeRequestGeneration == requestGeneration else { return }
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
            do {
                let outcome = try await capabilityExecutor.execute(command)
                try Task.checkCancellation()
                guard activeRequestGeneration == requestGeneration else { return }
                switch outcome {
                case let .result(result):
                    currentContext.replaceAnswer(result.primaryAnswer)
                    resultState = .deterministic(result)
                    LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=deterministic capability=\(command.intent.rawValue)")
                case let .handoff(result):
                    if result.kind == .system {
                        systemHandoffOpen(result.destination)
                        resultState = .idle
                    } else {
                        resultState = .webHandoff(result)
                    }
                    LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=handoff capability=\(command.intent.rawValue)")
                case let .presentation(presentation):
                    capabilityPresentation = presentation
                    resultState = .idle
                    LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=system_presentation capability=\(command.intent.rawValue)")
                case let .suspended(presentation, continuation):
                    capabilityContinuation = continuation
                    capabilityPresentation = presentation
                    resultState = .idle
                    LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=compound_presentation capability=\(command.intent.rawValue)")
                }
                statusText = AppText.value("ready")
            } catch is CancellationError {
                return
            } catch let CanonicalCapabilityExecutionError.ambiguous(values) {
                guard activeRequestGeneration == requestGeneration else { return }
                requireAction(prompt: AppText.value("clarification_needed"), choices: Array(values.prefix(3)))
                statusText = AppText.value("clarification_needed")
            } catch let CanonicalCapabilityExecutionError.missingParameter(parameter) {
                guard activeRequestGeneration == requestGeneration else { return }
                LocalVoiceDiagnosticReport.shared.record("router_rejected", "reason=missing_parameter parameter=\(parameter)")
                resultState = .clarification(summary)
                statusText = AppText.value("clarification_needed")
            } catch let CanonicalCapabilityExecutionError.externalProviderRequired(providerClass) {
                guard activeRequestGeneration == requestGeneration else { return }
                LocalVoiceDiagnosticReport.shared.record("execution_failed", "reason=external_provider_required capability=\(providerClass)")
                presentGeneralWebFallback(command)
            } catch let CanonicalCapabilityExecutionError.unavailable(reason) {
                guard activeRequestGeneration == requestGeneration else { return }
                LocalVoiceDiagnosticReport.shared.record("execution_failed", "reason=capability_unavailable capability=\(command.intent.rawValue) detail=\(reason)")
                presentFailure(message: AppText.value("request_unavailable"))
            } catch {
                guard activeRequestGeneration == requestGeneration else { return }
                LocalVoiceDiagnosticReport.shared.record("execution_failed", "reason=capability_unavailable capability=\(command.intent.rawValue)")
                presentFailure(message: AppText.value("request_unavailable"))
            }
        }
    }

    private func deliverCompletedDiagnosticSession() {
        if let session = LocalVoiceDiagnosticReport.shared.completedSession() {
            Task { await PhysicalDiagnosticDelivery.shared.enqueue(session) }
        }
    }

    func handleScannedCode(_ observation: ObservedScannerCode) {
        capabilityPresentation = nil
        do { resultState = .scanner(try ScannerProductionRouter().route(observation)); statusText = AppText.value("ready"); LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=scanner type=\(observation.isQR ? "qr" : "barcode")") }
        catch { presentFailure(message: AppText.value("request_unavailable")) }
    }
    func handleScannerUnavailable() { capabilityPresentation = nil; presentFailure(message: AppText.value("request_unavailable")) }
    func performScannerAction(_ result: ScannerProductionResult) {
        switch result.route.content {
        case let .url(url) where result.route.action == .open: UIApplication.shared.open(url)
        case let .text(value) where result.route.action == .save: UIPasteboard.general.string = value; statusText = AppText.value("ready")
        case let .text(value) where result.route.action == .call:
            let number = value.replacingOccurrences(of: "tel:", with: ""); if let url = URL(string: "tel:\(number.filter(\.isNumber))") { UIApplication.shared.open(url) }
        case let .vCard(data) where result.route.action == .importContact: capabilityPresentation = .contactImport(data)
        case let .retailBarcode(value):
            let command = StructuredCommand(originalText: "GTIN \(value)", normalizedText: "gtin \(value)", language: .automatic, intent: .productSearch, entities: ["query": "GTIN \(value)"])
            presentGeneralWebFallback(command)
        default: presentFailure(message: AppText.value("request_unavailable"))
        }
    }
    func performResultAction(_ action: ResultAction) {
        guard action.kind == .showPhoto, action.id.hasPrefix("photos:") else { return }
        capabilityPresentation = .photoAsset(String(action.id.dropFirst("photos:".count)))
    }

    func handleCapturedOCRImage(_ image: UIImage?) { processOCR(image, provenance: .camera) }
    func handlePhotoOCRImage(_ image: UIImage?) { processOCR(image, provenance: .photoLibrary) }
    func handleSelectedOCRDocuments(_ urls: [URL]) {
        capabilityPresentation = nil
        guard let url = urls.first else { presentFailure(message: AppText.value("request_unavailable")); return }
        let accessed = url.startAccessingSecurityScopedResource()
        let image = UIImage(contentsOfFile: url.path)
        if accessed { url.stopAccessingSecurityScopedResource() }
        processOCR(image, provenance: .document)
    }
    func handleScannedOCRDocument(_ pages: [UIImage]) {
        capabilityPresentation = nil
        guard !pages.isEmpty else { presentFailure(message: AppText.value("request_unavailable")); return }
        activeRequestGeneration &+= 1
        let requestGeneration = activeRequestGeneration
        ocrExecutionTask?.cancel()
        resultState = .processing
        ocrExecutionTask = Task { [weak self] in
            guard let self else { return }
            do {
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
    }
    private func processOCR(_ image: UIImage?, provenance: OCRInputProvenance) {
        capabilityPresentation = nil
        guard image != nil else { presentFailure(message: AppText.value("request_unavailable")); return }
        activeRequestGeneration &+= 1
        let requestGeneration = activeRequestGeneration
        ocrExecutionTask?.cancel()
        resultState = .processing
        ocrExecutionTask = Task { [weak self] in
            guard let self else { return }
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
        guard let continuation = capabilityContinuation,
              let executor = capabilityExecutor as? ProductionCanonicalCapabilityExecutor else { return }
        capabilityContinuation = nil
        activeRequestGeneration &+= 1
        let generation = activeRequestGeneration
        capabilityExecutionTask?.cancel()
        capabilityExecutionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let outcome = try await executor.resume(continuation, with: output)
                guard !Task.isCancelled, activeRequestGeneration == generation else { return }
                switch outcome {
                case let .result(value): resultState = .deterministic(value)
                case let .handoff(value):
                    if value.kind == .system || value.kind == .navigation {
                        systemHandoffOpen(value.destination)
                        resultState = .idle
                    } else {
                        resultState = .webHandoff(value)
                    }
                case let .presentation(value): capabilityPresentation = value; resultState = .idle
                case let .suspended(value, next): capabilityContinuation = next; capabilityPresentation = value; resultState = .idle
                }
                statusText = AppText.value("ready")
            } catch {
                guard !Task.isCancelled, activeRequestGeneration == generation else { return }
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
        do { capabilityPresentation = .translation(try CameraIntelligenceCore().translationPlan(text: text, sourceLanguage: nil, targetLanguage: targetLanguage)) }
        catch { capabilityPresentation = nil; presentFailure(message: AppText.value("request_unavailable")) }
    }
    func handleTranslationResult(_ result: TranslationProductionResult) { currentContext.replaceTranslation(sourceText: result.sourceText, sourceLanguage: result.sourceLanguage); capabilityPresentation = nil; resultState = .translation(result); statusText = AppText.value("ready"); LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=translation") }
    func handleTranslationFailure() { capabilityPresentation = nil; presentFailure(message: AppText.value("request_unavailable")) }
    func performTranslationAction(_ result: TranslationProductionResult, _ action: OCRResultAction) {
        switch action { case .copy: UIPasteboard.general.string = result.translatedText; case .share: capabilityPresentation = .share(result.translatedText); case .translate: break }
    }
    func dismissCapabilityPresentation() {
        capabilityPresentation = nil
        capabilityContinuation = nil
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
