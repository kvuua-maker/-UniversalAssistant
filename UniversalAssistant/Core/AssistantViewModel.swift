import CryptoKit
import Foundation
import Observation
import OSLog
import UIKit

/// Decides ownership before any pending continuation consumes fresh input.
/// It does not parse or route: it only compares the already parsed standalone
/// candidate with the narrowly missing role/visible choices.
struct PendingContinuationCompatibilityPolicy: Sendable {
    func shouldConsumeSelection(reply: String, standalone: StructuredCommand, choices: [String]) -> Bool {
        let candidates = choices.map {
            ScopedEntityCandidate(value: $0, displayName: $0, aliases: [$0, $0.split(separator: "·", maxSplits: 1).first.map(String.init) ?? $0])
        }
        if case .resolved = ContextScopedEntityResolver(candidates: candidates).resolve(reply) { return true }
        return !isIndependent(standalone) && isNarrowReply(reply)
    }

    func shouldConsumeClarification(reply: String, standalone: StructuredCommand, role: String) -> Bool {
        guard !isIndependent(standalone) else { return false }
        let normalized = CanonicalMorphology.comparableText(reply)
        switch role {
        case "time", "restaurant_date_time", "temporal":
            return normalized.range(of: #"\b(?:[01]?\d|2[0-3])[:.]?[0-5]\d\b"#, options: .regularExpression) != nil || isNarrowReply(reply)
        case "party_size", "quantity":
            return normalized.range(of: #"\b\d{1,2}\b"#, options: .regularExpression) != nil || isNarrowReply(reply)
        case "recipient", "message_body", "service_channel", "application":
            return isNarrowReply(reply)
        default:
            return isNarrowReply(reply)
        }
    }

    private func isIndependent(_ command: StructuredCommand) -> Bool {
        guard command.intent != .unknown, command.intent != .contextualSelection else { return false }
        if command.intent == .show, command.entities["context_reference"] != nil { return false }
        let actionRoots = ["відк", "знайд", "куп", "напиш", "подзвон", "набери", "покаж", "створ", "заброн", "перейд", "увімк", "включ", "open", "find", "buy", "call", "message", "show"]
        return actionRoots.contains(where: command.normalizedText.contains) ||
            [.emergency, .weather, .ticketSearch, .ticketPurchaseHandoff, .photoSearch].contains(command.intent)
    }

    private func isNarrowReply(_ reply: String) -> Bool {
        let tokens = reply.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard !tokens.isEmpty, tokens.count <= 5 else { return false }
        let actionRoots = ["відк", "знайд", "куп", "напиш", "подзвон", "набери", "покаж", "створ", "заброн", "open", "find", "buy", "call", "show"]
        return !tokens.contains { token in
            let value = CanonicalMorphology.comparableText(token)
            return actionRoots.contains(where: value.hasPrefix)
        }
    }
}

@MainActor
@Observable
final class AssistantViewModel {
    private static let voiceLogger = Logger(subsystem: "com.universalassistant.app", category: "VoicePipeline")
    var input = ""
    private(set) var visibleVoiceTranscript = ""
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
    private(set) var languageConfiguration = LanguageConfiguration()
    let recorder: AudioRecorderController
    private let commandEngine: any CommandParsing
    private let interactionEngine: any InteractionDeciding
    private let semanticCommandResolver: (any SemanticCommandResolving)?
    private let contacts: any ContactResolving
    private let capabilityExecutor: any CanonicalCapabilityExecuting
    private let productionRouter: SingleCorridorRouter
    private let productionCorridor: ProductionExecutionRoomOrchestrator
    private let currentContext: CurrentContextStore
    private let ocrPipeline: OCRProductionPipeline
    private let voiceInput: any VoiceInputControlling
    private let feedbackStore: UserFeedbackStore
    private let compactResultDuration: Duration
    private let presentationPreferenceStore: PresentationPreferenceStore
    private let systemHandoffOpenResult: @MainActor (URL) async -> Bool
    private let quickLaunchStore: QuickLaunchRequestStore
    private let personalTaskStore = PersonalTaskStore()
    private let favoriteStore = FavoriteStore()
    private let languageConfigurationStore = LanguageConfigurationStore()
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
    private var messageRoleCompletionTask: Task<Void, Never>?
    private var capabilityContinuation: CanonicalCapabilityContinuation?
    private var capabilityPresentationGeneration: UInt64?
    private var capabilityPresentationCommandID: UUID?
    // Own the permission-suspending microphone start from the UI lifecycle.
    // Controller generation guards suppress stale callbacks; this task ownership
    // also prevents abandoned starts surviving re-entry or scene transitions.
    private var voiceStartTask: Task<Void, Never>?
    private var voiceDraftSourceText: String?
    private var voiceContinuationPrefix: String?
    private var pendingVoiceRecognitionEvidence: VoiceRecognitionEvidence?
    private var voiceAutoSubmitArmed = false
    private var voiceSubmitPerformed = false
    private var pendingConfirmation: (command: StructuredCommand, summary: ResultSummary, generation: UInt64)?
    private var pendingCanonicalSelection: (command: StructuredCommand, summary: ResultSummary, generation: UInt64, role: String, choices: [String], identifiers: [String: String])?
    private var pendingCanonicalClarification: (command: StructuredCommand, summary: ResultSummary, generation: UInt64, role: String)?
    var voiceInputEngineIdentifier: String { voiceInput.engineIdentifier }
    var isVoiceOrbAvailable: Bool {
        voiceInputEnabled && ![.denied, .speechDenied, .unavailable].contains(voiceInput.state)
    }

    init(
        commandEngine: any CommandParsing = LanguageUnderstandingBlock(),
        interactionEngine: any InteractionDeciding = InteractionDecisionEngine(),
        weatherExecutor: any WeatherCommandExecuting = ProductionWeatherCommandExecutor(),
        webSearchHandoff: ControlledWebSearchHandoff = ControlledWebSearchHandoff(),
        genericDiscovery: GenericUnknownRequestCoordinator? = nil,
        semanticCommandResolver: (any SemanticCommandResolving)? = nil,
        contacts: any ContactResolving = LocalContactResolver(),
        eventKitExecutor: any EventKitCommandExecuting = ProductionEventKitCommandExecutor(),
        capabilityExecutor: (any CanonicalCapabilityExecuting)? = nil,
        configuredRestaurantReservationProviderIDs: Set<String> = [],
        currentContext suppliedCurrentContext: CurrentContextStore? = nil,
        ocrProcessor: (any DocumentOCRProcessing)? = nil,
        recorder: AudioRecorderController? = nil,
        feedbackStore: UserFeedbackStore = .shared,
        compactResultDuration: Duration = .seconds(2),
        presentationPreferenceStore: PresentationPreferenceStore = PresentationPreferenceStore(),
        voiceInput: any VoiceInputControlling = VoiceInputController(),
        notificationEnable: @escaping @MainActor () async -> ProactiveNotificationEnableResult = { await ProductionNotificationRegistration.enable() },
        quickLaunchStore: QuickLaunchRequestStore = QuickLaunchRequestStore(),
        systemHandoffOpen: (@MainActor (URL) -> Void)? = nil,
        systemHandoffOpenResult: (@MainActor (URL) async -> Bool)? = nil
    ) {
        // Resolve optional collaborators once, so the rest of the body (and the
        // orchestrator below) sees concrete values.
        let recorder = recorder ?? AudioRecorderController()
        self.commandEngine = commandEngine
        self.interactionEngine = interactionEngine
        self.semanticCommandResolver = semanticCommandResolver
        self.contacts = contacts
        self.productionRouter = SingleCorridorRouter(capabilities: .init(
            configuredRestaurantReservationProviderIDs: configuredRestaurantReservationProviderIDs
        ))
        let currentContext = suppliedCurrentContext ?? CurrentContextStore()
        self.currentContext = currentContext
        let resolvedCapabilityExecutor = capabilityExecutor ?? ProductionCanonicalCapabilityExecutor(currentContext: currentContext, recorder: recorder)
        self.capabilityExecutor = resolvedCapabilityExecutor
        self.productionCorridor = ProductionExecutionRoomOrchestrator(
            weather: weatherExecutor,
            eventKit: eventKitExecutor,
            capabilities: resolvedCapabilityExecutor,
            recorder: recorder,
            web: webSearchHandoff
        )
        self.ocrPipeline = OCRProductionPipeline(processor: ocrProcessor ?? OnDeviceDocumentOCR())
        self.recorder = recorder
        self.feedbackStore = feedbackStore
        self.compactResultDuration = compactResultDuration
        self.presentationPreferenceStore = presentationPreferenceStore
        self.voiceInput = voiceInput
        self.notificationEnable = notificationEnable
        self.quickLaunchStore = quickLaunchStore
        if let systemHandoffOpenResult {
            self.systemHandoffOpenResult = systemHandoffOpenResult
        } else if let systemHandoffOpen {
            // Test and host-app compatibility boundary: injected openers are
            // responsible for accepting the URL they capture.
            self.systemHandoffOpenResult = { destination in
                systemHandoffOpen(destination)
                return true
            }
        } else {
            // Production acceptance is the result reported by iOS, not the
            // mere construction of a URL.
            self.systemHandoffOpenResult = { destination in
                await UIApplication.shared.open(destination)
            }
        }
        voiceInput.setEventHandler { [weak self] event in
            self?.handleVoiceEvent(event)
        }
        Task { [weak self] in
            guard let self else { return }
            if let value = try? await presentationPreferenceStore.load() { self.presentationPreferences = value }
        }
        Task { [weak self] in
            guard let self else { return }
            await self.loadPersonalHub()
        }
        Task { [weak self] in
            guard let self else { return }
            if let value = try? await self.languageConfigurationStore.load() {
                self.languageConfiguration = value
                AppText.languageIdentifier = value.uiLanguage.rawValue
            }
        }
    }

    /// Applies the interface language chosen in Settings. Persisted separately
    /// from presentation preferences because it also drives command parsing.
    func setUILanguage(_ language: UILanguage) {
        languageConfiguration.uiLanguage = language
        AppText.languageIdentifier = language.rawValue
        let snapshot = languageConfiguration
        Task { [weak self] in
            guard let self else { return }
            try? await self.languageConfigurationStore.save(snapshot)
        }
    }

    // MARK: - Personal hub (My Tasks / Favorites)

    /// Restores the two first-class personal surfaces from protected local
    /// storage. Without this both tabs rendered their empty state forever.
    func loadPersonalHub() async {
        try? await personalTaskStore.restore()
        let storedTasks = await personalTaskStore.snapshot()
        personalTasks = PersonalTaskHub().aggregate(assistantOwned: storedTasks, systemReferences: [])
        try? await favoriteStore.restore()
        favorites = await favoriteStore.snapshot()
        await synchronizeFavorites()
    }

    /// Replicates favorites through the local-primary sync boundary. CloudKit is
    /// used only where the entitlement exists; otherwise the same contract is
    /// served by protected local storage, so an outage never blocks the UI.
    private func synchronizeFavorites() async {
        let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? "unidentified-device"
        let hub = PersonalHubSync()
        let coordinator = LocalPrimarySyncCoordinator(transport: SyncTransportFactory.make())
        let outcome = await coordinator.reconcile(local: hub.records(from: favorites, deviceID: deviceID))
        guard case let .synchronized(result) = outcome else { return }
        let merged = hub.favorites(from: result.records)
        if !merged.isEmpty { favorites = merged }
    }

    /// Records an assistant-owned consequential item (booking, created event or
    /// reminder) so it appears in My Tasks. System-owned records stay in their
    /// own frameworks and are never duplicated here.
    func recordPersonalTask(_ item: PersonalTaskItem) {
        Task { [weak self] in
            guard let self else { return }
            try? await personalTaskStore.upsert(item)
            let stored = await personalTaskStore.snapshot()
            self.personalTasks = PersonalTaskHub()
                .aggregate(assistantOwned: stored, systemReferences: [])
        }
    }

    func toggleFavorite(place: Place) {
        toggleFavorite(FavoriteReference(
            id: "place:\(place.id)", kind: .place,
            providerID: place.providerID ?? "apple-maps",
            externalReference: place.id,
            displayTitle: place.name,
            displaySubtitle: place.address,
            freshness: .unknown))
    }

    func toggleFavorite(offer presentation: CommerceOfferPresentation) {
        let offer = presentation.offer
        toggleFavorite(FavoriteReference(
            id: "product:\(offer.id)", kind: .product,
            providerID: offer.providerID,
            externalReference: offer.providerOfferID,
            displayTitle: presentation.title,
            displaySubtitle: offer.seller.name,
            freshness: .unknown))
    }

    func isFavorite(id: String) -> Bool { favorites.contains { $0.id == id } }

    private func toggleFavorite(_ reference: FavoriteReference) {
        let removing = favorites.contains { $0.id == reference.id }
        Task { [weak self] in
            guard let self else { return }
            if removing {
                try? await favoriteStore.remove(id: reference.id)
            } else {
                try? await favoriteStore.save(reference)
            }
            self.favorites = await favoriteStore.snapshot()
        }
    }

    func toggleListening() {
        guard voiceInputEnabled else {
            voiceInput.stop(reason: .voiceDisabled); isListening = false; statusText = AppText.value("voice_disabled")
            return
        }
        if isListening || voiceInput.state == .requestingPermission || voiceInput.state == .transcribing {
            voiceStartTask?.cancel()
            voiceStartTask = nil
            voiceInput.stop(reason: voiceInput.state == .listening ? .userPressedStop : .externalRequest)
            isListening = false
        } else {
            voiceStartTask?.cancel()
            voiceStartTask = Task { [weak self] in
                guard let self else { return }
                await voiceInput.start(locale: Locale(identifier: "uk-UA"))
                guard !Task.isCancelled else { return }
                applyVoiceState(voiceInput.state)
                voiceStartTask = nil
            }
        }
    }

    func applyVoiceState(_ state: VoiceInputState) {
        isListening = state == .listening
        shouldOfferSettings = state == .denied || state == .speechDenied
        statusText = switch state {
                case .listening: AppText.value("listening")
                case .transcribing: AppText.value("processing")
                case .denied: AppText.value("microphone_denied")
                case .speechDenied: AppText.value("speech_unavailable")
                case .unavailable: AppText.value("speech_unavailable")
                case .failed: AppText.value("listening_failed")
                default: AppText.value("ready")
        }
    }

    func handleVoiceEvent(_ event: VoiceInputEvent) {
        switch event {
        case let .state(state):
            LocalVoiceDiagnosticReport.shared.record("state_delivered_to_view_model", "state=\(String(describing: state))")
            if state == .requestingPermission {
                voiceDraftSourceText = nil
                pendingVoiceRecognitionEvidence = nil
                voiceAutoSubmitArmed = true
                voiceSubmitPerformed = false
                visibleVoiceTranscript = ""
            }
            if state == .idle { voiceAutoSubmitArmed = false }
            applyVoiceState(state)
            if [.denied, .speechDenied, .unavailable, .failed].contains(state) {
                voiceAutoSubmitArmed = false
                LocalVoiceDiagnosticReport.shared.recordTerminal(
                    [.denied, .speechDenied].contains(state) ? .permissionRequired : .error,
                    details: "stage=voice_input state=\(String(describing: state))"
                )
            }
            if [.idle, .denied, .speechDenied, .unavailable, .failed].contains(state),
               !weatherExecutionInFlight, !eventKitExecutionInFlight, !capabilityExecutionInFlight,
               let session = LocalVoiceDiagnosticReport.shared.completedSession() {
                Task { await PhysicalDiagnosticDelivery.shared.enqueue(session) }
            }
        case let .recognitionEvidence(evidence):
            pendingVoiceRecognitionEvidence = evidence
        case let .transcript(transcript, isFinal):
            guard voiceAutoSubmitArmed, !voiceSubmitPerformed else {
                LocalVoiceDiagnosticReport.shared.record("stale_voice_transcript_rejected", "final=\(isFinal)")
                return
            }
            let visibleTranscript = VoiceTranscriptStabilizer.normalizedForDisplay(transcript)
            input = visibleTranscript
            visibleVoiceTranscript = visibleTranscript
            LocalVoiceDiagnosticReport.shared.recordVoiceText("VISIBLE_TRANSCRIPT", text: visibleTranscript, details: "final=\(isFinal)")
            LocalVoiceDiagnosticReport.shared.record("transcript_delivered_to_view_model", "length=\(transcript.count) final=\(isFinal)")
            Self.voiceLogger.notice("transcript_delivered_to_view_model length=\(transcript.count, privacy: .public) final=\(isFinal, privacy: .public)")
            if isFinal, !visibleTranscript.isEmpty {
                voiceDraftSourceText = visibleTranscript
                voiceSubmitPerformed = true
                voiceAutoSubmitArmed = false
                Self.voiceLogger.notice("voice_transcript_ready_for_auto_submit")
                LocalVoiceDiagnosticReport.shared.recordVoiceText("AUTO_SUBMIT_PRE", text: visibleTranscript)
                LocalVoiceDiagnosticReport.shared.recordVoiceText("SUBMITTED_TEXT", text: visibleTranscript)
                LocalVoiceDiagnosticReport.shared.record("REQUEST_ID", "request_id=\(LocalVoiceDiagnosticReport.shared.currentRequestIdentifier.uuidString.lowercased())")
                submit()
            }
        }
    }

    /// Called only by the editable composer. Manual input owns the field and
    /// invalidates a pending voice submit so a late callback cannot overwrite it.
    func updateComposerTextFromUser(_ value: String) {
        if voiceAutoSubmitArmed {
            voiceAutoSubmitArmed = false
            voiceSubmitPerformed = true
            voiceStartTask?.cancel()
            voiceStartTask = nil
            voiceInput.stop(reason: .externalRequest)
            LocalVoiceDiagnosticReport.shared.record("voice_auto_submit_cancelled", "reason=manual_edit")
        }
        input = value
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
        // A clipped command ("Відкрий") is completed by the next phrase; the
        // prefix is merged here so the parser sees one full command.
        if let prefix = voiceContinuationPrefix {
            input = prefix + " " + input
            voiceContinuationPrefix = nil
        }
        let isVoiceSubmission = voiceDraftSourceText != nil
        let voiceEvidence = voiceDraftSourceText == input ? pendingVoiceRecognitionEvidence : nil
        let standaloneCommand = if let parser = commandEngine as? any EvidenceAwareCommandParsing {
            parser.parse(input, speechEvidence: voiceEvidence)
        } else {
            commandEngine.parse(input)
        }
        // A clipped utterance such as "Відкрий" carries no object; restart the
        // microphone once instead of routing an impossible command.
        if isVoiceSubmission,
           input.split(separator: " ").count < 2,
           standaloneCommand.intent == .open || standaloneCommand.intent == .appAction,
           standaloneCommand.entities["app"] == nil,
           voiceContinuationPrefix == nil {
            voiceContinuationPrefix = input
            RuntimeDiagnostics.shared.log("voice", "short utterance '\(input)' -> keep listening")
            statusText = "Слухаю… назвіть застосунок"
            input = ""
            toggleListening()
            return
        }
        RuntimeDiagnostics.shared.log(
            "heard", "\(isVoiceSubmission ? "voice" : "typed"): \(input)")
        RuntimeDiagnostics.shared.log(
            "intent",
            "\(standaloneCommand.intent.rawValue)"
                + " app=\(standaloneCommand.entities["app"] ?? "-")"
                + " service=\(standaloneCommand.entities["call_service"] ?? standaloneCommand.entities["message_service"] ?? "-")")
        let continuationPolicy = PendingContinuationCompatibilityPolicy()
        if let pending = pendingCanonicalSelection,
           pending.generation == activeRequestGeneration,
           continuationPolicy.shouldConsumeSelection(reply: input, standalone: standaloneCommand, choices: pending.choices),
           consumePendingSelectionReplyIfPossible(input) { return }
        if let pending = pendingCanonicalClarification,
           pending.generation == activeRequestGeneration,
           continuationPolicy.shouldConsumeClarification(reply: input, standalone: standaloneCommand, role: pending.role),
           resumePendingClarificationIfPossible(input) { return }
        pendingVoiceRecognitionEvidence = nil
        if voiceDraftSourceText != nil {
            LocalVoiceDiagnosticReport.shared.record("transcript_delivered_to_router", "length=\(input.count)")
            voiceDraftSourceText = nil
        }
        resultDismissTask?.cancel()
        activeRequestGeneration &+= 1
        let requestGeneration = activeRequestGeneration
        if LocalVoiceDiagnosticReport.shared.finishInteractiveContinuation(.cancelled, details: "reason=superseded") {
            deliverCompletedDiagnosticSession()
        }
        LocalVoiceDiagnosticReport.shared.beginHomeRequest(generation: requestGeneration)
        if isVoiceSubmission {
            LocalVoiceDiagnosticReport.shared.record("AUTO_SUBMIT_POST", "status=accepted")
        }
        capabilityExecutionTask?.cancel()
        ocrExecutionTask?.cancel()
        weatherExecutionTask?.cancel()
        eventKitExecutionTask?.cancel()
        genericDiscoveryTask?.cancel()
        messageRoleCompletionTask?.cancel()
        // A newly submitted command supersedes any UI-bound continuation.
        // Late picker/scanner/OCR callbacks therefore cannot resume an obsolete request.
        capabilityContinuation = nil
        capabilityPresentationGeneration = nil
        capabilityPresentationCommandID = nil
        capabilityPresentation = nil
        pendingConfirmation = nil
        pendingCanonicalSelection = nil
        pendingCanonicalClarification = nil
        weatherExecutionInFlight = false
        eventKitExecutionInFlight = false
        capabilityExecutionInFlight = false
        let submittedInput = input
        let requestEnvelope = CanonicalRequestEnvelope(
            requestID: UUID(),
            source: isVoiceSubmission ? .voice : .typed,
            originalText: submittedInput,
            appleFinalTranscript: voiceEvidence?.primaryTranscript,
            appleAlternatives: voiceEvidence?.alternativeTranscripts ?? [],
            appleSegmentAlternatives: voiceEvidence?.segmentAlternativeTranscripts ?? [],
            partialHistory: voiceEvidence?.partialTranscriptHistory ?? [],
            groqTranscript: nil,
            language: .automatic
        )
        LocalVoiceDiagnosticReport.shared.record("canonical_request_envelope", "request_id=\(requestEnvelope.requestID.uuidString)")
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
        let command = standaloneCommand
        if Self.requiresContactAwareMessageCompletion(command) {
            input = ""
            messageRoleCompletionTask?.cancel()
            messageRoleCompletionTask = Task { [weak self] in
                guard let self else { return }
                try? await contacts.requestAccessIfNeeded()
                let vocabulary = await contacts.contextualVocabulary(limit: 120)
                guard !Task.isCancelled, activeRequestGeneration == requestGeneration else { return }
                let enriched = Self.completingMessageRoles(command, contactVocabulary: vocabulary)
                finishResolvedCommand(enriched, requestGeneration: requestGeneration)
            }
            return
        }
        finishResolvedCommand(command, requestGeneration: requestGeneration)
    }

    private func finishResolvedCommand(_ command: StructuredCommand, requestGeneration: UInt64) {
        guard activeRequestGeneration == requestGeneration else { return }
        LocalVoiceDiagnosticReport.shared.recordNormalizedTranscript(command.normalizedText)
        LocalVoiceDiagnosticReport.shared.record("canonical_command_ready", "intent=\(command.intent.rawValue)")
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
        let summary = ResultSummary(request: command.originalText, intent: command.intent, risk: command.risk)
        interactionDecision = interactionEngine.decide(for: command)
        input = ""
        if command.intent == .unknown, !command.needsClarification,
           command.entities["clarification_options"] == nil {
            LocalVoiceDiagnosticReport.shared.record("semantic_engine_selection", "engine=groq reason=deterministic_unresolved")
            LocalVoiceDiagnosticReport.shared.record("semantic_cloud_used", "value=true")
            resolveSemanticCommand(
                original: command,
                summary: summary,
                requestGeneration: requestGeneration
            )
            return
        }
        LocalVoiceDiagnosticReport.shared.record("semantic_cloud_used", "value=false")
        dispatchResolvedCommand(command, requestGeneration: requestGeneration)
    }

    private func consumePendingSelectionReplyIfPossible(_ reply: String) -> Bool {
        guard let pending = pendingCanonicalSelection,
              pending.generation == activeRequestGeneration,
              !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let candidates = pending.choices.map { choice in
            let shortName = choice.split(separator: "·", maxSplits: 1).first.map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? choice
            return ScopedEntityCandidate(value: choice, displayName: choice, aliases: [choice, shortName])
        }
        let resolver = ContextScopedEntityResolver(candidates: candidates)
        guard case let .resolved(choice) = resolver.resolve(reply) else {
            input = ""
            voiceDraftSourceText = nil
            pendingVoiceRecognitionEvidence = nil
            requireAction(prompt: AppText.value("clarification_needed"), choices: pending.choices)
            return true
        }
        input = ""
        voiceDraftSourceText = nil
        pendingVoiceRecognitionEvidence = nil
        resolveActionRequiredChoice(choice)
        return true
    }

    private func resumePendingClarificationIfPossible(_ reply: String) -> Bool {
        guard let pending = pendingCanonicalClarification,
              pending.generation == activeRequestGeneration else { return false }
        let trimmedReply = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReply.isEmpty else { return true }
        let combinedText = pending.command.originalText + " " + trimmedReply
        let resolved = commandEngine.parse(combinedText)
        guard pending.command.intent == .unknown || resolved.intent == pending.command.intent else {
            input = ""
            voiceDraftSourceText = nil
            pendingVoiceRecognitionEvidence = nil
            presentClarification(message: AppText.value("clarification_needed"), summary: pending.summary)
            return true
        }
        let protectedKeys = [
            "message_service", "call_service", "provider", "explicit_provider",
            "brand", "app", "explicit_location"
        ]
        var entities = resolved.entities
        for key in protectedKeys {
            if let original = pending.command.entities[key] {
                if let replacement = entities[key],
                   CanonicalMorphology.comparableText(replacement) != CanonicalMorphology.comparableText(original) {
                    input = ""
                    voiceDraftSourceText = nil
                    pendingVoiceRecognitionEvidence = nil
                    presentClarification(message: AppText.value("clarification_needed"), summary: pending.summary)
                    return true
                }
                entities[key] = original
            }
        }
        activeRequestGeneration &+= 1
        let generation = activeRequestGeneration
        pendingCanonicalClarification = nil
        input = ""
        voiceDraftSourceText = nil
        pendingVoiceRecognitionEvidence = nil
        resumeInteractiveDiagnosticContinuation(generation: generation)
        let resumed = StructuredCommand(
            id: pending.command.id,
            originalText: combinedText,
            normalizedText: resolved.normalizedText,
            language: resolved.language,
            intent: resolved.intent,
            entities: entities,
            constraints: resolved.constraints,
            risk: resolved.risk,
            needsClarification: resolved.needsClarification
        )
        if Self.requiresContactAwareMessageCompletion(resumed) {
            messageRoleCompletionTask?.cancel()
            messageRoleCompletionTask = Task { [weak self] in
                guard let self else { return }
                try? await contacts.requestAccessIfNeeded()
                let vocabulary = await contacts.contextualVocabulary(limit: 120)
                guard !Task.isCancelled, activeRequestGeneration == generation else { return }
                finishResolvedCommand(
                    Self.completingMessageRoles(resumed, contactVocabulary: vocabulary),
                    requestGeneration: generation
                )
            }
        } else {
            finishResolvedCommand(resumed, requestGeneration: generation)
        }
        return true
    }

    private static func requiresContactAwareMessageCompletion(_ command: StructuredCommand) -> Bool {
        guard command.intent == .messageCompose else { return false }
        let recipientWords = command.entities["recipient"]?.split(whereSeparator: \.isWhitespace).count ?? 0
        return recipientWords > 1 || command.entities["message_body"] == nil
    }

    private static func completingMessageRoles(
        _ command: StructuredCommand,
        contactVocabulary: [String]
    ) -> StructuredCommand {
        guard let roles = CanonicalMessageRoleAnalyzer.analyzeContactAware(
            command.originalText,
            explicitService: command.entities["message_service"],
            contactVocabulary: contactVocabulary
        ) else { return command }
        var entities = command.entities
        if let recipient = roles.recipient {
            entities["recipient"] = recipient
        } else if let body = roles.body,
                  let currentRecipient = entities["recipient"],
                  CanonicalMorphology.comparableText(currentRecipient) == CanonicalMorphology.comparableText(body) {
            // A colon introduces content. If the structural first pass copied
            // that same content into RECIPIENT, the contact-aware completion
            // removes only the duplicated role; it does not guess a person.
            entities.removeValue(forKey: "recipient")
        }
        if let body = roles.body { entities["message_body"] = body }
        let needsClarification: Bool
        if !roles.ambiguousRecipients.isEmpty {
            entities["clarification_role"] = "recipient"
            entities["clarification_options"] = roles.ambiguousRecipients.joined(separator: "|")
            needsClarification = true
        } else {
            needsClarification = command.needsClarification
        }
        return .init(
            id: command.id,
            originalText: command.originalText,
            normalizedText: command.normalizedText,
            language: command.language,
            intent: command.intent,
            entities: entities,
            constraints: command.constraints,
            risk: command.risk,
            needsClarification: needsClarification
        )
    }

    private func resolveSemanticCommand(
        original: StructuredCommand,
        summary: ResultSummary,
        requestGeneration: UInt64
    ) {
        guard let semanticCommandResolver else {
            dispatchResolvedCommand(
                .init(id: original.id, originalText: original.originalText, normalizedText: original.normalizedText,
                      language: original.language, intent: .webSearch, entities: ["query": original.originalText],
                      constraints: original.constraints, risk: .informational, needsClarification: false),
                requestGeneration: requestGeneration
            )
            return
        }
        resultState = .processing
        statusText = AppText.value("processing")
        genericDiscoveryTask = Task { [weak self] in
            guard let self else { return }
            do {
                let resolved = try await semanticCommandResolver.resolveCommand(
                    original.originalText,
                    language: original.language
                )
                try Task.checkCancellation()
                guard activeRequestGeneration == requestGeneration else { return }
                LocalVoiceDiagnosticReport.shared.record(
                    "semantic_frame_validated",
                    "engine=groq intent=\(resolved.intent.rawValue) schema=valid"
                )
                dispatchResolvedCommand(resolved, requestGeneration: requestGeneration)
            } catch GenericDiscoveryError.ambiguous {
                guard !Task.isCancelled, activeRequestGeneration == requestGeneration else { return }
                resultState = .clarification(summary)
                statusText = AppText.value("clarification_needed")
                LocalVoiceDiagnosticReport.shared.recordTerminal(.clarification)
                deliverCompletedDiagnosticSession()
            } catch GroqLanguageServiceError.privacyBlocked {
                guard !Task.isCancelled, activeRequestGeneration == requestGeneration else { return }
                LocalVoiceDiagnosticReport.shared.recordTerminal(.unsupported, details: "reason=never_ai_privacy_gate")
                presentFailure(message: "Цей запит містить захищені дані й обробляється лише локально.")
                deliverCompletedDiagnosticSession()
            } catch {
                guard !Task.isCancelled, activeRequestGeneration == requestGeneration else { return }
                LocalVoiceDiagnosticReport.shared.record(
                    "semantic_engine_fallback",
                    "engine=groq reason=unavailable_or_invalid"
                )
                dispatchResolvedCommand(
                    .init(id: original.id, originalText: original.originalText, normalizedText: original.normalizedText,
                          language: original.language, intent: .webSearch, entities: ["query": original.originalText],
                          constraints: original.constraints, risk: .informational, needsClarification: false),
                    requestGeneration: requestGeneration
                )
            }
        }
    }

    private func dispatchResolvedCommand(_ command: StructuredCommand, requestGeneration: UInt64) {
        let summary = ResultSummary(request: command.originalText, intent: command.intent, risk: command.risk)
        interactionDecision = interactionEngine.decide(for: command)
        if command.needsClarification, let raw = command.entities["clarification_options"] {
            let choices = Array(raw.split(separator: "|").map(String.init).prefix(3))
            pendingCanonicalSelection = (
                command, summary, requestGeneration,
                command.entities["clarification_role"] ?? Self.selectionRole(for: command, choices: choices),
                choices, [:]
            )
            LocalVoiceDiagnosticReport.shared.suspendForInteractiveContinuation("canonical-clarification", generation: requestGeneration)
            requireAction(prompt: AppText.value("clarification_needed"), choices: choices)
            return
        }
        if command.needsClarification {
            pendingCanonicalClarification = (
                command,
                summary,
                requestGeneration,
                command.entities["clarification_role"] ?? "target"
            )
            LocalVoiceDiagnosticReport.shared.suspendForInteractiveContinuation(
                "canonical-clarification",
                generation: requestGeneration
            )
            resultState = .clarification(summary)
            statusText = AppText.value("clarification_needed")
            return
        }
        if interactionDecision?.pattern == .confirmation {
            requireConfirmation(command, summary: summary, generation: requestGeneration)
            return
        }
        let plan = frozenPlan(for: command)
        LocalVoiceDiagnosticReport.shared.record(
            "system_first_decision",
            "selected=\(plan.routingDecision.lane == .appleSystem) capability=\(command.intent.rawValue)"
        )
        LocalVoiceDiagnosticReport.shared.record(
            "generic_web_selected",
            "selected=\(plan.room == .web) reason=predetermined_room"
        )
        LocalVoiceDiagnosticReport.shared.record(
            "current_context_input",
            "input_type=\(currentContext.diagnosticInputType())"
        )
        LocalVoiceDiagnosticReport.shared.record(
            "router_received",
            "capability=\(command.intent.rawValue) language=\(command.language.rawValue)"
        )
        LocalVoiceDiagnosticReport.shared.record(
            "routing_policy_decision",
            "lane=\(plan.routingDecision.lane.rawValue) room=\(plan.room.rawValue) " +
                "provider=\(plan.providerID ?? "none") reason=\(plan.routingDecision.reason) route_count=1"
        )
        LocalVoiceDiagnosticReport.shared.record("router_accepted", "room=\(plan.room.rawValue)")
        LocalVoiceDiagnosticReport.shared.record("execution_started", "mechanism=\(plan.primaryMechanism)")
        LocalVoiceDiagnosticReport.shared.record("permission_state", "status=executor_managed")
        resultState = .processing
        statusText = AppText.value("processing")
        capabilityExecutionInFlight = true
        capabilityExecutionTask = Task { [weak self] in
            guard let self else { return }
            LocalVoiceDiagnosticReport.shared.record("EXECUTOR_PRE", "room=\(plan.room.rawValue)")
            let outcome = await productionCorridor.execute(plan)
            guard !Task.isCancelled, activeRequestGeneration == requestGeneration else { return }
            LocalVoiceDiagnosticReport.shared.record("EXECUTOR_POST", "room=\(plan.room.rawValue)")
            LocalVoiceDiagnosticReport.shared.record("RENDERER_ACTION_PRE", "room=\(plan.room.rawValue)")
            await render(outcome, command: command, generation: requestGeneration)
            LocalVoiceDiagnosticReport.shared.record("RENDERER_ACTION_POST", "room=\(plan.room.rawValue)")
            capabilityExecutionInFlight = false
            deliverCompletedDiagnosticSession()
        }
    }

    // External informational and provider web destinations are selected by
    // SingleCorridorRouter and executed by the Web room, never after failure.

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

    private func openSystemHandoffObserved(_ destination: URL) async -> Bool {
        let scheme = destination.scheme?.lowercased()
        if let scheme {
            let known = ["tg", "viber", "whatsapp", "spotify", "youtube", "maps", "comgooglemaps", "waze"].contains(scheme)
            let installable = known ? UIApplication.shared.canOpenURL(destination) : true
            RuntimeDiagnostics.shared.log(
                "scheme",
                "\(scheme):// canOpenURL=\(installable)")
        }
        let boundary = scheme == "tel" ? "CALL_URL" : "EXACT_HANDOFF"
        LocalVoiceDiagnosticReport.shared.recordBoundaryPre(boundary, "scheme=\(scheme ?? "unknown")")
        let opened = await systemHandoffOpenResult(destination)
        RuntimeDiagnostics.shared.log("openURL", "\(destination.absoluteString) -> \(opened ? "opened" : "rejected")")
        LocalVoiceDiagnosticReport.shared.recordBoundaryPost(
            boundary,
            "scheme=\(scheme ?? "unknown") status=\(opened ? "opened" : "rejected")"
        )
        return opened
    }

    private func render(
        _ outcome: ProductionTerminalOutcome,
        command: StructuredCommand,
        generation: UInt64
    ) async {
        guard activeRequestGeneration == generation else { return }
        switch outcome {
        case let .weather(snapshot):
            resultState = .weather(snapshot)
            statusText = AppText.value("ready")
            LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=weather")
        case let .eventKit(result):
            resultState = .eventKit(result)
            statusText = AppText.value("ready")
            LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=eventkit")
            if result.operation == .created {
                recordPersonalTask(PersonalTaskItem(
                    id: "assistant:\(command.intent.rawValue):\(result.title)",
                    kind: result.kind == .calendar ? .appointment : .unfinished,
                    source: .assistant,
                    externalReference: result.title,
                    title: result.title,
                    status: .confirmed,
                    relevantAt: nil,
                    verifiedAt: Date()))
            }
        case let .exactWeb(result):
            resultState = .webHandoff(result)
            statusText = AppText.value("ready")
            LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=predetermined_exact_web")
        case let .clarify(summary):
            resultState = .clarification(summary)
            statusText = AppText.value("clarification_needed")
            LocalVoiceDiagnosticReport.shared.recordTerminal(.clarification)
        case let .choices(values):
            let choices = Array(values.prefix(8))
            pendingCanonicalSelection = (
                command, .init(request: command.originalText, intent: command.intent, risk: command.risk), generation,
                Self.selectionRole(for: command, choices: choices), choices, [:]
            )
            requireAction(prompt: AppText.value("clarification_needed"), choices: choices)
        case let .contactChoices(values):
            var occurrences: [String: Int] = [:]
            var choices: [String] = []
            var identifiers: [String: String] = [:]
            for value in values {
                let base = value.selectionLabel
                let occurrence = (occurrences[base] ?? 0) + 1
                occurrences[base] = occurrence
                let label = occurrence == 1 ? base : "\(base) · \(occurrence)"
                choices.append(label)
                identifiers[label] = value.identifier
            }
            pendingCanonicalSelection = (
                command, .init(request: command.originalText, intent: command.intent, risk: command.risk), generation,
                "contact_identifier", choices, identifiers
            )
            requireAction(prompt: "Оберіть потрібний контакт", choices: choices)
        case let .confirm(prepared):
            requireConfirmation(
                prepared,
                summary: .init(request: command.originalText, intent: command.intent, risk: .consequential),
                generation: generation
            )
        case let .systemInstruction(message):
            presentFailure(message: message)
            LocalVoiceDiagnosticReport.shared.recordTerminal(.unsupported, details: "terminal_contract=SYSTEM_INSTRUCTION")
        case let .audioRecorder(action, state, url):
            if state == .failed || state == .denied {
                presentFailure(message: "iPhone не дозволив почати запис. Перевірте доступ до мікрофона в Налаштуваннях.")
            } else {
                resultState = .idle
                statusText = AppText.value("ready")
                if action == .stop, state == .stopped, let url {
                    currentContext.replaceShared(kind: .document, value: url.path)
                    capabilityPresentation = .audioFile(url)
                }
            }
        case let .capability(capability):
            switch capability {
            case let .result(result):
                currentContext.replaceAnswer(result.primaryAnswer)
                resultState = .deterministic(result)
            case let .placeResults(places):
                resultState = .placeResults(places)
            case let .commerceResults(offers):
                resultState = .commerceResults(offers)
            case let .jobResults(jobs):
                resultState = .jobResults(jobs)
            case let .handoff(result):
                if (result.kind == .system || result.kind == .navigation || result.kind == .provider) &&
                    !result.requiresExplicitUserActivation {
                    if await openSystemHandoffObserved(result.destination) {
                        resultState = .idle
                    } else {
                        presentFailure(message: "iPhone відхилив точний перехід. Перевірте, чи встановлено потрібний застосунок.")
                    }
                } else {
                    resultState = .webHandoff(result)
                }
            case let .presentation(presentation):
                LocalVoiceDiagnosticReport.shared.suspendForInteractiveContinuation(presentation.id)
                capabilityPresentation = presentation
                capabilityPresentationGeneration = presentation.id == "contact-access" ? generation : nil
                capabilityPresentationCommandID = presentation.id == "contact-access" ? command.id : nil
                resultState = .idle
            case let .suspended(presentation, continuation):
                LocalVoiceDiagnosticReport.shared.suspendForInteractiveContinuation(presentation.id)
                capabilityContinuation = continuation
                capabilityPresentation = presentation
                resultState = .idle
            }
            statusText = AppText.value("ready")
            LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=capability room=single_corridor")
        }
    }

    private func executeCanonicalCapability(_ command: StructuredCommand, summary: ResultSummary, requestGeneration: UInt64) {
        executeFrozenCommand(command, requestGeneration: requestGeneration)
    }

    private func executeFrozenCommand(_ command: StructuredCommand, requestGeneration: UInt64) {
        let plan = frozenPlan(for: command)
        LocalVoiceDiagnosticReport.shared.record("route_plan_ready", "room=\(plan.room.rawValue) route_count=1")
        resultState = .processing
        statusText = AppText.value("processing")
        capabilityExecutionInFlight = true
        capabilityExecutionTask = Task { [weak self] in
            guard let self else { return }
            LocalVoiceDiagnosticReport.shared.record("room_started", "room=\(plan.room.rawValue)")
            let outcome = await productionCorridor.execute(plan)
            guard !Task.isCancelled, activeRequestGeneration == requestGeneration else { return }
            await render(outcome, command: command, generation: requestGeneration)
            capabilityExecutionInFlight = false
            deliverCompletedDiagnosticSession()
        }
    }

    private func frozenPlan(for command: StructuredCommand) -> RoutePlan {
        guard command.intent == .multiStep else { return productionRouter.plan(command) }
        // Compound clauses are resolved at the authoritative resolution
        // boundary. The router receives immutable atomic commands and the
        // coordinator never reparses while executing.
        let atomic = CompoundCommandClauses.split(command.originalText)
            .map(commandEngine.parse)
            .filter { $0.intent != .unknown && $0.intent != .multiStep }
        return productionRouter.planCompound(container: command, atomicCommands: atomic)
    }

    private func truthfulSystemRestrictionMessage(_ reason: String) -> String {
        if reason.contains("system_settings") {
            return "iPhone не дозволяє стороннім застосункам відкривати цей системний розділ. Відкрийте Налаштування вручну."
        }
        if reason.contains("voice_memos") {
            return "iPhone не надає публічного способу відкрити або запустити системний Диктофон з іншого застосунку."
        }
        if reason.contains("viber") || reason.contains("telegram") || reason.contains("signal") {
            return "Цей застосунок не надає підтвердженого публічного переходу для запитаної дії."
        }
        return "Ця дія недоступна через публічні можливості iPhone."
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
            let exact = "GTIN \(value)"
            let command = StructuredCommand(
                originalText: exact,
                normalizedText: exact.lowercased(),
                language: .automatic,
                intent: .productSearch,
                entities: ["query": exact, "gtin": value, "identity_strength": "exact"]
            )
            // The scanner has already validated the checksum. If no first-
            // party catalogue provider is connected, continue with the exact
            // GTIN instead of terminating at a provider-connection message.
            dispatchResolvedCommand(command, requestGeneration: activeRequestGeneration)
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
    func selectPDFCreationSource(_ source: PDFCreationSource, suggestedText: String?) {
        switch source {
        case .text: capabilityPresentation = .pdfTextInput(suggestedText)
        case .photo: capabilityPresentation = .pdfPhotoPicker
        case .document: capabilityPresentation = .pdfWorkflow(.create, text: nil)
        case .choose: capabilityPresentation = .pdfSourcePicker(.choose, text: suggestedText)
        }
    }
    func createPDFFromText(_ text: String) {
        do {
            let data = try OnDevicePDFProcessor().textPDF(text)
            let url = try persistPDF(data)
            currentContext.replaceShared(kind: .document, value: url.path)
            capabilityPresentation = .documentFile(url)
            resultState = .idle; statusText = AppText.value("ready")
            LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=document_pdf source=text")
        } catch {
            presentFailure(message: AppText.value("request_unavailable"))
        }
    }
    func handleSelectedPDFPhoto(_ identifier: String?) {
        guard let identifier else { dismissCapabilityPresentation(); return }
        capabilityPresentation = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                let imageData = try await PhotoKitAssetImageLoader().imageData(localIdentifier: identifier)
                guard let image = UIImage(data: imageData) else { throw PDFProcessingError.invalidPDF }
                let data = try OnDevicePDFProcessor().searchablePDF(images: [image], recognizedText: [""])
                let url = try persistPDF(data)
                currentContext.replaceShared(kind: .document, value: url.path)
                capabilityPresentation = .documentFile(url)
                resultState = .idle; statusText = AppText.value("ready")
                LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=document_pdf source=photo")
            } catch {
                presentFailure(message: AppText.value("request_unavailable"))
            }
        }
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
            case .create: outputs = [try processor.convertedDocument(data[0])]
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
    private func persistPDF(_ data: Data) throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appending(path: "UniversalAssistant/PDF", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let url = base.appending(path: "PDF-Result-\(UUID().uuidString).pdf")
        try data.write(to: url, options: .atomic)
        return url
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
                let processor = OnDevicePDFProcessor()
                let preparedPages = pages.map { (try? processor.scanEnhanced($0)) ?? $0 }
                if mode == .pdf {
                    var recognized: [String] = []
                    for image in preparedPages {
                        recognized.append((try? await ocrPipeline.process(image, provenance: .document).recognizedText) ?? "")
                    }
                    let data = try processor.searchablePDF(images: preparedPages, recognizedText: recognized)
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
                let result = try await ocrPipeline.process(preparedPages, provenance: .document)
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
                case let .placeResults(values):
                    resultState = .placeResults(values)
                    LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=compound_places")
                case let .commerceResults(values):
                    resultState = .commerceResults(values)
                    LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=compound_commerce")
                case let .jobResults(values):
                    resultState = .jobResults(values)
                    LocalVoiceDiagnosticReport.shared.record("visible_result", "kind=compound_jobs")
                case let .handoff(value):
                    if (value.kind == .system || value.kind == .navigation || value.kind == .provider) &&
                        !value.requiresExplicitUserActivation {
                        guard await openSystemHandoffObserved(value.destination) else {
                            throw CanonicalCapabilityExecutionError.unavailable("exact_handoff_rejected")
                        }
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
            let resumed = Self.command(
                pending.command,
                selecting: pending.identifiers[choice] ?? choice,
                role: pending.role
            )
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
        executeFrozenCommand(pending.command, requestGeneration: pending.generation)
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
        case "contact_identifier":
            entities["contact_identifier"] = choice
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
        statusText = prompt
        resultState = .actionRequired(.init(prompt: prompt, choices: choices))
    }

    func presentFailure(message: String, recoveryAction: String? = nil) {
        RuntimeDiagnostics.shared.log("result", "failure: \(message)")
        resultDismissTask?.cancel()
        statusText = message
        resultState = .failure(.init(message: message, recoveryAction: recoveryAction))
    }

    private func presentClarification(message: String, summary: ResultSummary) {
        resultDismissTask?.cancel()
        statusText = message
        resultState = .clarification(summary)
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
