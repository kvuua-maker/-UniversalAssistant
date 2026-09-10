import AVFoundation
import Observation
import OSLog
import Speech
import UIKit

enum VoiceInputState: Equatable, Sendable { case idle, requestingPermission, listening, denied, unavailable, failed }

enum VoiceInputEvent: Equatable, Sendable {
    case state(VoiceInputState)
    case recognitionEvidence(VoiceRecognitionEvidence)
    case transcript(String, isFinal: Bool)
}

struct VoiceRecognitionEvidence: Equatable, Sendable {
    let primaryTranscript: String
    let alternativeTranscripts: [String]
    let segmentAlternativeCount: Int
    let averageSegmentConfidence: Double?
}

enum VoiceStopReason: String, Sendable {
    case sessionRestart, externalRequest, userPressedStop, voiceDisabled, sceneInactive
    case recognitionFinal, recognitionError, audioInterruption, routeChange, startFailure
}

private enum VoiceDiagnostic {
    static let logger = Logger(subsystem: "com.universalassistant.app", category: "VoicePipeline")
}

final class LocalVoiceDiagnosticReport: @unchecked Sendable {
    struct Entry: Codable, Sendable { let timestamp: Date; let marker: String; let details: String }
    private struct LegacyPersisted: Codable { let sessionID: UUID; let startedAt: Date; let entries: [Entry] }
    static let shared = LocalVoiceDiagnosticReport()
    private let lock = NSLock()
    private var entries: [Entry] = []
    private let diagnosticSessionID = UUID()
    private var requestID = UUID()
    private var requestGeneration: UInt64 = 0
    private var startedAt = Date()
    private var finalSpeechTranscript: String?
    private var normalizedTranscript: String?
    private var explicitTerminalState: DiagnosticTerminalState?
    private var interactiveContinuationPending = false
    private let defaults: UserDefaults
    private let persistenceKey: String
    private let localStore: PhysicalDiagnosticLocalStore
    private let crashlyticsRecorder: any CrashlyticsDiagnosticRecording
    private var legacyRecovered: LegacyPersisted?
    private static let maximumDeliveredEvents = 250
    private static let detailedConsentKey = "build32-detailed-diagnostics-consent"
    private static let safeAttributeKeys: Set<String> = [
        "state", "granted", "available", "locale", "input", "sample_rate", "channels", "running", "count", "frames",
        "partial_results", "punctuation", "task_hint", "api", "has_text", "final", "error_domain", "error_code",
        "partial_count", "final_count", "reason", "had_task", "had_request", "length", "input_available", "error_type",
        "status", "capability", "language", "mechanism", "kind", "alternatives", "segment_alternatives", "confidence_bucket",
        "context_count", "on_device_supported", "on_device_required", "generation", "source", "selected", "domain", "candidate_count",
        "confidence", "confidence_margin", "object", "action", "destination", "service", "app", "date", "time", "duration",
        "constraint_count", "target", "person", "location", "constraints", "candidate_fingerprints",
        "contact_identifier_hash", "photo_asset_id_hash", "url_host_class", "coarse_location_role", "ocr_block_count", "ocr_confidence",
        "input_type", "output_type", "permission", "terminal", "stage", "last_stage", "last_pre", "last_post",
        "missing_expected_post", "http_status", "schema", "detailed", "scheme", "operation", "provider", "route", "result",
        "parameter", "pages", "type", "accepted", "confirmed", "elapsed_ms", "fallback"
    ]

    init(
        defaults: UserDefaults = .standard,
        persistenceKey: String = "physical-diagnostic-active-request-v1",
        localStore: PhysicalDiagnosticLocalStore = .shared,
        crashlyticsRecorder: any CrashlyticsDiagnosticRecording = CrashlyticsDiagnosticBridge.shared
    ) {
        self.defaults = defaults
        self.persistenceKey = persistenceKey
        self.localStore = localStore
        self.crashlyticsRecorder = crashlyticsRecorder
        if let data = defaults.data(forKey: persistenceKey),
           let value = try? JSONDecoder().decode(LegacyPersisted.self, from: data) {
            legacyRecovered = value
        }
    }

    var diagnosticSessionIdentifier: UUID { diagnosticSessionID }

    var detailedDiagnosticsEnabled: Bool {
        get { defaults.bool(forKey: Self.detailedConsentKey) }
        set { defaults.set(newValue, forKey: Self.detailedConsentKey) }
    }

    func reset() {
        lock.lock()
        entries = []
        requestID = UUID()
        requestGeneration = 0
        startedAt = .now
        finalSpeechTranscript = nil
        normalizedTranscript = nil
        explicitTerminalState = nil
        interactiveContinuationPending = false
        beginDurableRequestLocked()
        lock.unlock()
    }

    func beginHomeRequest(generation: UInt64 = 0) {
        lock.lock()
        let latestVoiceIngress = entries.lastIndex(where: { $0.marker == "transcript_delivered_to_router" })
        let latestHomeRequest = entries.lastIndex(where: { $0.marker == "home_request_started" })
        let hasFreshVoiceIngress = latestVoiceIngress.map { voiceIndex in
            latestHomeRequest.map { voiceIndex > $0 } ?? true
        } ?? false
        if !hasFreshVoiceIngress {
            entries = []
            requestID = UUID()
            startedAt = .now
            finalSpeechTranscript = nil
            normalizedTranscript = nil
            explicitTerminalState = nil
            interactiveContinuationPending = false
        }
        requestGeneration = generation
        beginDurableRequestLocked()
        appendLocked("request_created", "source=home generation=\(generation)", durable: true)
        appendLocked("home_request_started", "source=home generation=\(generation)", durable: true)
        lock.unlock()
    }

    func record(_ marker: String, _ details: String = "") {
        let safeDetails = Self.privacySafeDetails(details)
        lock.lock()
        // Scene, MetricKit, and other ambient callbacks can arrive while no
        // command is active. They must not manufacture a crash-suspected Home
        // request. Real voice and typed requests create the durable snapshot in
        // reset()/beginHomeRequest() before their first command marker.
        if localStore.activeSnapshot() != nil {
            appendLocked(marker, safeDetails, durable: marker.hasSuffix("_PRE") || marker == "request_created")
        }
        lock.unlock()
        VoiceDiagnostic.logger.notice("\(marker, privacy: .public) \(safeDetails, privacy: .public)")
    }

    func recordBoundaryPre(_ boundary: String, _ details: String = "") {
        record("\(boundary)_PRE", details)
    }

    func recordBoundaryPost(_ boundary: String, _ details: String = "") {
        record("\(boundary)_POST", details)
    }

    func recordSpeechTranscript(_ transcript: String, isFinal: Bool) {
        guard isFinal else {
            record("partial_transcript", "length=\(transcript.count)")
            return
        }
        lock.lock()
        finalSpeechTranscript = Self.privacySafeTranscript(transcript)
        appendLocked("final_transcript", "length=\(transcript.count) detailed=\(detailedDiagnosticsEnabled)", durable: true)
        crashlyticsRecorder.recordTranscript(
            transcript,
            normalized: false,
            sequence: entries.count,
            identity: crashlyticsIdentityLocked(),
            detailedDiagnosticsEnabled: detailedDiagnosticsEnabled
        )
        if detailedDiagnosticsEnabled {
            localStore.updateActive(
                sequence: entries.count,
                stage: "final_transcript",
                detailedDiagnosticsConsent: true,
                finalSpeechTranscript: finalSpeechTranscript
            )
        }
        lock.unlock()
    }

    func recordNormalizedTranscript(_ transcript: String) {
        lock.lock()
        normalizedTranscript = Self.privacySafeTranscript(transcript)
        appendLocked("normalization", "length=\(transcript.count)", durable: false)
        crashlyticsRecorder.recordTranscript(
            transcript,
            normalized: true,
            sequence: entries.count,
            identity: crashlyticsIdentityLocked(),
            detailedDiagnosticsEnabled: detailedDiagnosticsEnabled
        )
        if detailedDiagnosticsEnabled {
            localStore.updateActive(
                sequence: entries.count,
                stage: "normalization",
                detailedDiagnosticsConsent: true,
                normalizedTranscript: normalizedTranscript
            )
        }
        lock.unlock()
    }

    func recordTerminal(_ state: DiagnosticTerminalState, details: String = "") {
        lock.lock()
        explicitTerminalState = state
        appendLocked("terminal_request_state", "state=\(state.rawValue) \(details)", durable: true)
        localStore.updateActive(sequence: entries.count, stage: "terminal_request_state", terminal: state)
        lock.unlock()
    }

    func suspendForInteractiveContinuation(_ kind: String, generation: UInt64? = nil) {
        lock.lock()
        interactiveContinuationPending = true
        if let generation {
            requestGeneration = generation
            localStore.updateActive(sequence: entries.count, stage: "interactive_continuation_suspended", generation: generation)
        }
        appendLocked("interactive_continuation_suspended", "kind=\(String(kind.prefix(64))) generation=\(generation ?? requestGeneration)", durable: true)
        lock.unlock()
    }

    func resumeInteractiveContinuation(generation: UInt64? = nil) {
        lock.lock()
        guard interactiveContinuationPending else { lock.unlock(); return }
        interactiveContinuationPending = false
        if let generation {
            requestGeneration = generation
            localStore.updateActive(sequence: entries.count, stage: "interactive_continuation_resumed", generation: generation)
        }
        appendLocked("interactive_continuation_resumed", "generation=\(generation ?? requestGeneration)", durable: true)
        lock.unlock()
    }

    @discardableResult
    func finishInteractiveContinuation(_ state: DiagnosticTerminalState, details: String = "") -> Bool {
        lock.lock()
        guard interactiveContinuationPending else { lock.unlock(); return false }
        interactiveContinuationPending = false
        explicitTerminalState = state
        appendLocked("interactive_continuation_finished", "state=\(state.rawValue) \(details)", durable: true)
        appendLocked("terminal_request_state", "state=\(state.rawValue)", durable: true)
        localStore.updateActive(sequence: entries.count, stage: "terminal_request_state", terminal: state)
        lock.unlock()
        return true
    }

    func snapshot() -> String {
        lock.lock(); defer { lock.unlock() }
        let lines = entries.enumerated().map { "\($0.offset + 1). \($0.element.marker)\($0.element.details.isEmpty ? "" : " | \($0.element.details)")" }
        return (["UniversalAssistant Local Diagnostic Black Box", "Raw microphone audio is never recorded."] + lines).joined(separator: "\n")
    }

    @MainActor func recoveredIncompleteSession() -> PhysicalDiagnosticSession? {
        lock.lock(); defer { lock.unlock() }
        if let active = localStore.consumeUncleanActiveRequest() {
            let missing = active.lastPRE.flatMap { pre in
                let expected = DiagnosticAnomalyAnalyzer.pairedPost(for: pre)
                return expected == active.lastPOST ? nil : expected
            }
            let anomaly = DiagnosticAnomaly(
                anomalyClass: .uncleanTermination,
                certainty: .probableFailureBoundary,
                stage: active.lastPRE ?? active.lastStage,
                reason: missing.map { "missing_expected_post:\($0)" } ?? "request_not_terminal"
            )
            localStore.setLastAnomaly(anomaly)
            let now = Date()
            var uncleanEvent = PhysicalDiagnosticEvent(
                sequence: 1, timestamp: now, marker: "unclean_termination_detected",
                attributes: [
                    "last_stage": active.lastStage,
                    "last_pre": active.lastPRE ?? "none",
                    "last_post": active.lastPOST ?? "none",
                    "missing_expected_post": missing ?? "unknown"
                ]
            )
            uncleanEvent.diagnosticSessionID = active.diagnosticSessionID
            uncleanEvent.requestID = active.requestID
            uncleanEvent.requestGeneration = active.requestGeneration
            uncleanEvent.build = active.build
            let prior = localStore.events(for: active.requestID)
            let preserved = (prior + [uncleanEvent]).suffix(Self.maximumDeliveredEvents)
            let events = preserved.enumerated().map { index, source in
                var event = PhysicalDiagnosticEvent(
                    sequence: index + 1,
                    timestamp: source.timestamp,
                    marker: source.marker,
                    attributes: source.attributes
                )
                event.diagnosticSessionID = active.diagnosticSessionID
                event.requestID = active.requestID
                event.requestGeneration = active.requestGeneration
                event.build = active.build
                return event
            }
            let recoveredStart = events.first?.timestamp ?? active.updatedAt
            var session = PhysicalDiagnosticSession(
                schema: 2, sessionID: active.requestID, liveTestID: "BUILD32-PRODUCTION-BLACK-BOX", feature: "request",
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                build: active.build, environment: "internal-testflight", osVersion: UIDevice.current.systemVersion,
                deviceClass: UIDevice.current.model, startedAt: recoveredStart, endedAt: now,
                durationMilliseconds: max(0, Int(now.timeIntervalSince(recoveredStart) * 1_000)),
                result: .crashSuspected, failureStage: anomaly.stage,
                errorDomain: "ProcessTerminatedBeforeTerminalResult", errorCode: -1, events: events
            )
            session.diagnosticSessionID = active.diagnosticSessionID
            session.requestID = active.requestID
            session.requestGeneration = active.requestGeneration
            session.terminalState = .error
            session.detailedDiagnosticsConsent = active.detailedDiagnosticsConsent
            session.finalSpeechTranscript = active.detailedDiagnosticsConsent ? active.finalSpeechTranscript : nil
            session.normalizedTranscript = active.detailedDiagnosticsConsent ? active.normalizedTranscript : nil
            session.anomaly = anomaly
            localStore.addPending(Self.queued(session))
            crashlyticsRecorder.recordRecoveredUncleanSession(session)
            return session
        }
        guard let value = legacyRecovered, !value.entries.isEmpty else { return nil }
        legacyRecovered = nil
        defaults.removeObject(forKey: persistenceKey)
        let bounded = Self.boundedForDelivery(value.entries)
        let events = bounded.enumerated().map { index, entry in
            PhysicalDiagnosticEvent(sequence: index + 1, timestamp: entry.timestamp, marker: entry.marker, attributes: [:])
        }
        let ended = value.entries.last?.timestamp ?? value.startedAt
        return .init(schema: 1, sessionID: value.sessionID, liveTestID: "MS-800-RECOVERED-REQUEST", feature: "request",
                     appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                     build: Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0,
                     environment: "internal-testflight", osVersion: UIDevice.current.systemVersion, deviceClass: UIDevice.current.model,
                     startedAt: value.startedAt, endedAt: ended, durationMilliseconds: max(0, Int(ended.timeIntervalSince(value.startedAt) * 1_000)),
                     result: .failure, failureStage: value.entries.last?.marker,
                     errorDomain: "ProcessTerminatedBeforeTerminalResult", errorCode: -1, events: events)
    }

    @MainActor func completedSession() -> PhysicalDiagnosticSession? {
        lock.lock(); defer { lock.unlock() }
        guard !interactiveContinuationPending,
              entries.contains(where: { ["start_listening_invoked", "home_request_started"].contains($0.marker) }),
              let terminalState = explicitTerminalState ?? inferredTerminalStateLocked() else { return nil }
        if !entries.contains(where: { $0.marker == "terminal_request_state" }) {
            appendLocked("terminal_request_state", "state=\(terminalState.rawValue)", durable: true)
            localStore.updateActive(sequence: entries.count, stage: "terminal_request_state", terminal: terminalState)
        }
        let bounded = Self.boundedForDelivery(entries)
        let events = bounded.enumerated().map { index, entry in
            PhysicalDiagnosticEvent(
                sequence: index + 1,
                timestamp: entry.timestamp,
                marker: entry.marker,
                attributes: Self.privacySafeAttributes(entry.details)
            )
        }
        let error = events.reversed().first {
            let domain = $0.attributes["error_domain"]
            let code = $0.attributes["error_code"].flatMap(Int.init) ?? 0
            return (domain != nil && domain != "none") || code != 0
        }
        let result: PhysicalDiagnosticResult = terminalState == .success ? .success : (terminalState == .cancelled ? .interrupted : .failure)
        let ended = entries.last?.timestamp ?? .now
        let consent = detailedDiagnosticsEnabled
        var session = PhysicalDiagnosticSession(
            schema: 2, sessionID: requestID, liveTestID: "BUILD32-PRODUCTION-BLACK-BOX",
            feature: entries.contains(where: { $0.marker == "start_listening_invoked" }) ? "voice" : "request",
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            build: Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0,
            environment: "internal-testflight", osVersion: UIDevice.current.systemVersion, deviceClass: UIDevice.current.model,
            startedAt: startedAt, endedAt: ended, durationMilliseconds: max(0, Int(ended.timeIntervalSince(startedAt) * 1_000)),
            result: result, failureStage: terminalState == .success ? nil : (error?.marker ?? events.reversed().first(where: { $0.marker != "terminal_request_state" })?.marker),
            errorDomain: error?.attributes["error_domain"], errorCode: error?.attributes["error_code"].flatMap(Int.init), events: events
        )
        session.diagnosticSessionID = diagnosticSessionID
        session.requestID = requestID
        session.requestGeneration = requestGeneration
        session.terminalState = terminalState
        session.detailedDiagnosticsConsent = consent
        session.finalSpeechTranscript = consent ? finalSpeechTranscript : nil
        session.normalizedTranscript = consent ? normalizedTranscript : nil
        session.anomaly = DiagnosticAnomalyAnalyzer.analyze(events: events)
        if let anomaly = session.anomaly { localStore.setLastAnomaly(anomaly) }
        localStore.addPending(Self.queued(session))
        localStore.updateActive(sequence: entries.count, stage: "terminal_request_state", terminal: terminalState)
        localStore.clearTerminalActiveRequest()
        defaults.removeObject(forKey: persistenceKey)
        crashlyticsRecorder.recordTerminal(session)
        return session
    }

    private func appendLocked(_ marker: String, _ details: String, durable: Bool) {
        let safeDetails = Self.privacySafeDetails(details)
        let entry = Entry(timestamp: .now, marker: marker, details: safeDetails)
        entries.append(entry)
        if entries.count > 1_000 { entries.removeFirst(entries.count - 1_000) }
        let attributes = Self.privacySafeAttributes(safeDetails)
        var event = PhysicalDiagnosticEvent(sequence: entries.count, timestamp: entry.timestamp, marker: marker, attributes: attributes)
        event.diagnosticSessionID = diagnosticSessionID
        event.requestID = requestID
        event.requestGeneration = requestGeneration
        event.build = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
        localStore.append(event, durable: durable)
        localStore.updateActive(
            sequence: entries.count, stage: marker,
            pre: marker.hasSuffix("_PRE") ? marker : nil,
            post: marker.hasSuffix("_POST") ? marker : nil,
            capability: attributes["capability"]
        )
        crashlyticsRecorder.recordEvent(
            marker,
            details: safeDetails,
            sequence: entries.count,
            identity: crashlyticsIdentityLocked()
        )
    }

    private func beginDurableRequestLocked() {
        let snapshot = DiagnosticActiveRequestSnapshot(
            diagnosticSessionID: diagnosticSessionID, requestID: requestID, requestGeneration: requestGeneration,
            build: Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0,
            eventSequence: entries.count, lastStage: entries.last?.marker ?? "REQUEST_CREATED", lastPRE: nil, lastPOST: nil,
            selectedCapability: nil, terminal: false, terminalState: nil,
            detailedDiagnosticsConsent: detailedDiagnosticsEnabled,
            finalSpeechTranscript: detailedDiagnosticsEnabled ? finalSpeechTranscript : nil,
            normalizedTranscript: detailedDiagnosticsEnabled ? normalizedTranscript : nil,
            updatedAt: .now
        )
        localStore.begin(snapshot)
        let inputMode = entries.contains(where: { ["start_listening_invoked", "final_transcript", "transcript_delivered_to_router"].contains($0.marker) }) ? "voice" : "unknown"
        crashlyticsRecorder.beginRequest(crashlyticsIdentityLocked(), inputMode: inputMode)
    }

    private func crashlyticsIdentityLocked() -> CrashlyticsDiagnosticRequestIdentity {
        CrashlyticsDiagnosticRequestIdentity(
            diagnosticSessionID: diagnosticSessionID,
            requestID: requestID,
            generation: requestGeneration,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            build: Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
        )
    }

    private func inferredTerminalStateLocked() -> DiagnosticTerminalState? {
        if entries.contains(where: { $0.marker == "visible_result" }) { return .success }
        if entries.contains(where: { $0.marker == "router_rejected" && $0.details.contains("clarification") }) { return .clarification }
        if entries.contains(where: { $0.marker == "execution_failed" && $0.details.contains("external_provider_required") }) { return .providerRequired }
        if entries.contains(where: { entry in
            let attributes = Self.parseAttributes(entry.details)
            let domain = attributes["error_domain"]
            let code = attributes["error_code"].flatMap(Int.init) ?? 0
            return (domain != nil && domain != "none") || code != 0 || entry.marker.hasSuffix("_failed")
        }) { return .error }
        if entries.contains(where: { $0.marker == "execution_failed" }) { return .error }
        if entries.contains(where: { $0.marker == "state_transition" && $0.details.contains("idle") }) { return .cancelled }
        return nil
    }

    private static func parseAttributes(_ details: String) -> [String: String] {
        Dictionary(uniqueKeysWithValues: details.split(separator: " ").compactMap { token in
            let parts = token.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[0].count <= 64 else { return nil }
            return (parts[0], String(parts[1].prefix(256)))
        })
    }

    private static func privacySafeAttributes(_ details: String) -> [String: String] {
        parseAttributes(details).reduce(into: [String: String]()) { output, item in
            guard safeAttributeKeys.contains(item.key) else { return }
            output[item.key] = privacySafeTranscript(item.value)
        }
    }

    private static func privacySafeDetails(_ details: String) -> String {
        privacySafeAttributes(details)
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
    }

    private static func privacySafeTranscript(_ value: String) -> String {
        var result = String(value.prefix(512))
        let patterns = [
            #"(?i)https?://\S+"#,
            #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            #"(?<!\d)\+?\d[\d\s()\-]{5,}\d(?!\d)"#,
            #"(?i)\b(?:bearer|token|password|пароль)\s*[:=]?\s*\S+"#
        ]
        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: "[REDACTED]", options: .regularExpression)
        }
        return result
    }

    private static func queued(_ session: PhysicalDiagnosticSession) -> DiagnosticQueuedUpload {
        .init(session: session, attempts: 0, expiresAt: Date().addingTimeInterval(7 * 86_400),
              nextAttemptAt: .now, status: .pendingUpload, lastHTTPStatus: nil, errorCategory: nil)
    }

    private static func boundedForDelivery(_ source: [Entry]) -> [Entry] {
        guard source.count > maximumDeliveredEvents else { return source }
        let ingressCount = 100
        return Array(source.prefix(ingressCount)) + Array(source.suffix(maximumDeliveredEvents - ingressCount))
    }
}

private final class VoiceBufferDiagnosticCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func record(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        count += 1
        let current = count
        lock.unlock()
        if current == 1 || current.isMultiple(of: 100) {
            LocalVoiceDiagnosticReport.shared.record("audio_buffer_received", "count=\(current) frames=\(buffer.frameLength)")
        }
    }
}

enum VoiceAudioCaptureError: Error, Equatable {
    case invalidInputFormat
}

struct VoiceRecognitionRequestConfiguration: Sendable {
    let contextualVocabulary: [String]
    let requireOnDeviceRecognition: Bool

    init(additionalVocabulary: [String] = [], requireOnDeviceRecognition: Bool = false) {
        contextualVocabulary = Self.boundedVocabulary(additional: additionalVocabulary)
        self.requireOnDeviceRecognition = requireOnDeviceRecognition
    }

    static var canonicalVocabulary: [String] {
        let applications = LaunchDeviceApplications.verified.flatMap {
            [$0.id] + Array($0.aliases)
        }
        let services = MessengerKind.allCases.map(\.rawValue)
        let functions = [
            "UniversalAssistant", "Apple Music", "подкаст", "календар",
            "нагадування", "маршрут", "погода", "контакт", "нотатка",
            "документ", "файл", "світлина", "будильник", "таймер",
            "QR-код", "QR code", "OCR", "відкрий", "запусти",
            "відскануй", "розпізнай", "знайди", "покажи", "проклади",
            "подзвони", "набери", "повідомлення", "переклади", "ліхтарик"
        ]
        return boundedVocabulary(additional: applications + services + functions, includeCanonical: false)
    }

    static func boundedVocabulary(additional: [String], includeCanonical: Bool = true) -> [String] {
        var seen: Set<String> = []
        // Request-scoped candidates are the most relevant evidence for the
        // current utterance. Keep them ahead of the shared vocabulary so the
        // Speech framework's 100-entry limit cannot evict the very entities
        // supplied for this recognition request.
        let source = additional + (includeCanonical ? canonicalVocabulary : [])
        return source.compactMap { phrase -> String? in
            let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.split(whereSeparator: \.isWhitespace).count <= 2 else { return nil }
            let key = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "uk_UA"))
            guard seen.insert(key).inserted else { return nil }
            return trimmed
        }.prefix(100).map { $0 }
    }

    func apply(to request: SFSpeechAudioBufferRecognitionRequest, recognizer: SFSpeechRecognizer? = nil) {
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .search
        request.contextualStrings = contextualVocabulary
        request.requiresOnDeviceRecognition = requireOnDeviceRecognition && recognizer?.supportsOnDeviceRecognition == true
    }
}

@MainActor
protocol VoiceAudioCaptureBackend: AnyObject {
    func configureSession() throws
    func installTap(_ receive: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws
    func startEngine() throws
    func stop()
}

@MainActor
final class AppleVoiceAudioCaptureBackend: VoiceAudioCaptureBackend {
    private let audioEngine = AVAudioEngine()
    private var tapInstalled = false

    func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetoothHFP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        let input = session.currentRoute.inputs.first?.portType.rawValue ?? "none"
        LocalVoiceDiagnosticReport.shared.record("audio_session_activated", "input=\(input) sample_rate=\(session.sampleRate)")
    }

    func installTap(_ receive: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw VoiceAudioCaptureError.invalidInputFormat
        }
        LocalVoiceDiagnosticReport.shared.record("audio_tap_installed", "sample_rate=\(format.sampleRate) channels=\(format.channelCount)")
        input.installTap(onBus: 0, bufferSize: 1_024, format: format,
                         block: Self.makeTapHandler(receive))
        tapInstalled = true
    }

    nonisolated static func makeTapHandler(
        _ receive: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) -> AVAudioNodeTapBlock {
        let counter = VoiceBufferDiagnosticCounter()
        return { buffer, _ in
            counter.record(buffer)
            receive(buffer)
        }
    }

    func startEngine() throws {
        audioEngine.prepare()
        try audioEngine.start()
        LocalVoiceDiagnosticReport.shared.record("audio_engine_started", "running=\(audioEngine.isRunning)")
    }

    func stop() {
        LocalVoiceDiagnosticReport.shared.record("audio_capture_stop", "running=\(audioEngine.isRunning)")
        if audioEngine.isRunning { audioEngine.stop() }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

@MainActor
struct VoiceAudioCaptureLifecycle {
    let backend: any VoiceAudioCaptureBackend

    func start(receive: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        do {
            try backend.configureSession()
            try backend.installTap(receive)
            try backend.startEngine()
        } catch {
            backend.stop()
            throw error
        }
    }

    func stop() { backend.stop() }
}

private final class VoiceRecognitionRequestSink: @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest
    private let lock = NSLock()
    private var appendedCount = 0
    private var active = true

    init(_ request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        guard active else { lock.unlock(); return }
        appendedCount += 1
        let current = appendedCount
        request.append(buffer)
        lock.unlock()
        if current == 1 || current.isMultiple(of: 100) {
            LocalVoiceDiagnosticReport.shared.record("buffer_appended", "count=\(current)")
        }
    }

    /// Audio-tap callbacks run on a realtime queue. Deactivation must happen
    /// before `endAudio`/task cancellation so a queued callback cannot append
    /// to a request whose Speech lifecycle has already ended.
    func deactivate() {
        lock.lock(); active = false; lock.unlock()
    }
}

@MainActor
final class VoiceEndOfSpeechFinalizer {
    private let delay: Duration
    private var pending: Task<Void, Never>?

    init(delay: Duration = .milliseconds(1_200)) {
        self.delay = delay
    }

    func receivedPartial(_ finish: @escaping @MainActor @Sendable () -> Void) {
        pending?.cancel()
        let delay = delay
        pending = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    func cancel() {
        pending?.cancel()
        pending = nil
    }
}

@MainActor
@Observable
final class VoiceInputController {
    private(set) var state: VoiceInputState = .idle
    private(set) var transcript = ""
    private let capture: VoiceAudioCaptureLifecycle
    private let authorization: @Sendable () async -> Bool
    private let contextualVocabulary: @Sendable () async -> [String]
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var requestSink: VoiceRecognitionRequestSink?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    // start() suspends for permissions; a newer mic tap can supersede it.
    // One token owns every resource and callback for one Speech/audio session.
    private var activeSessionID: UUID?
    private let endOfSpeechFinalizer: VoiceEndOfSpeechFinalizer
    private var isFinalizingRecognition = false
    @ObservationIgnored private var audioEvents: AudioSessionEventMonitor?
    @ObservationIgnored private var eventHandler: (@MainActor @Sendable (VoiceInputEvent) -> Void)?
    @ObservationIgnored private var recognitionCallbackCount = 0
    @ObservationIgnored private var partialResultCount = 0
    @ObservationIgnored private var finalResultCount = 0

    init(
        captureBackend: (any VoiceAudioCaptureBackend)? = nil,
        endOfSpeechDelay: Duration = .milliseconds(2_000),
        authorization: (@Sendable () async -> Bool)? = nil,
        contextualVocabulary: @escaping @Sendable () async -> [String] = { [] }
    ) {
        capture = VoiceAudioCaptureLifecycle(backend: captureBackend ?? AppleVoiceAudioCaptureBackend())
        self.authorization = authorization ?? Self.authorizationGranted
        self.contextualVocabulary = contextualVocabulary
        endOfSpeechFinalizer = VoiceEndOfSpeechFinalizer(delay: endOfSpeechDelay)
        audioEvents = AudioSessionEventMonitor(
            onInterruption: { [weak self] in self?.handleAudioInterruptionBegan() },
            onRouteChange: { [weak self] evidence in self?.handleAudioRouteChanged(evidence) })
    }

    func start(locale: Locale = .current) async {
        stop(reason: .sessionRestart)
        let sessionID = UUID()
        activeSessionID = sessionID
        LocalVoiceDiagnosticReport.shared.reset()
        recognitionCallbackCount = 0
        partialResultCount = 0
        finalResultCount = 0
        isFinalizingRecognition = false
        LocalVoiceDiagnosticReport.shared.record("mic_tap", "source=home")
        LocalVoiceDiagnosticReport.shared.record("start_listening_invoked")
        setState(.requestingPermission)
        guard await authorization() else {
            guard owns(sessionID) else { return }
            activeSessionID = nil
            setState(.denied)
            return
        }
        guard owns(sessionID) else {
            LocalVoiceDiagnosticReport.shared.record("stale_start_suppressed", "reason=authorization_completed")
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            activeSessionID = nil
            setState(.unavailable)
            return
        }
        LocalVoiceDiagnosticReport.shared.record("recognizer_ready", "locale=\(locale.identifier) available=\(recognizer.isAvailable)")
        self.recognizer = recognizer
        let requestVocabulary = await contextualVocabulary()
        guard owns(sessionID) else {
            LocalVoiceDiagnosticReport.shared.record("stale_start_suppressed", "reason=context_vocabulary_completed")
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        let configuration = VoiceRecognitionRequestConfiguration(additionalVocabulary: requestVocabulary)
        configuration.apply(to: request, recognizer: recognizer)
        LocalVoiceDiagnosticReport.shared.record(
            "recognition_request_created",
            "api=sfspeechrecognizer partial_results=true punctuation=true task_hint=search context_count=\(configuration.contextualVocabulary.count) on_device_supported=\(recognizer.supportsOnDeviceRecognition) on_device_required=\(request.requiresOnDeviceRecognition)"
        )
        self.request = request
        let requestSink = VoiceRecognitionRequestSink(request)
        self.requestSink = requestSink
        LocalVoiceDiagnosticReport.shared.recordBoundaryPre("SPEECH_START", "locale=\(locale.identifier)")
        do {
            task = recognizer.recognitionTask(with: request, resultHandler: Self.makeRecognitionHandler(owner: self, sessionID: sessionID))
            LocalVoiceDiagnosticReport.shared.record("recognition_task_created")
            try capture.start { buffer in requestSink.append(buffer) }
            guard owns(sessionID) else {
                stop(reason: .sessionRestart, ownedBy: sessionID)
                return
            }
            setState(.listening)
            LocalVoiceDiagnosticReport.shared.recordBoundaryPost("SPEECH_START", "locale=\(locale.identifier) status=success")
        } catch {
            guard owns(sessionID) else { return }
            LocalVoiceDiagnosticReport.shared.record("voice_start_failed", "error_type=\(String(describing: type(of: error)))")
            stop(reason: .startFailure, ownedBy: sessionID); setState(.failed)
        }
    }

    func stop(reason: VoiceStopReason = .externalRequest) {
        stop(reason: reason, ownedBy: nil)
    }

    private func stop(reason: VoiceStopReason, ownedBy expectedSessionID: UUID?) {
        if let expectedSessionID, !owns(expectedSessionID) {
            LocalVoiceDiagnosticReport.shared.record("stale_stop_suppressed", "reason=\(reason.rawValue)")
            return
        }
        activeSessionID = nil
        endOfSpeechFinalizer.cancel()
        isFinalizingRecognition = false
        LocalVoiceDiagnosticReport.shared.record("stop_invoked", "reason=\(reason.rawValue)")
        let hadTask = task != nil
        let hadRequest = request != nil
        requestSink?.deactivate(); requestSink = nil
        task?.cancel(); task = nil; request?.endAudio(); request = nil
        LocalVoiceDiagnosticReport.shared.record("recognition_task_cancelled", "reason=\(reason.rawValue) had_task=\(hadTask)")
        LocalVoiceDiagnosticReport.shared.record("end_audio_called", "reason=\(reason.rawValue) had_request=\(hadRequest)")
        capture.stop()
        if state == .listening || state == .requestingPermission { setState(.idle) }
    }

    func setEventHandler(_ handler: @escaping @MainActor @Sendable (VoiceInputEvent) -> Void) {
        eventHandler = handler
    }

    private func setState(_ newState: VoiceInputState) {
        state = newState
        LocalVoiceDiagnosticReport.shared.record("state_transition", "state=\(String(describing: newState))")
        eventHandler?(.state(newState))
    }

    private func receiveRecognition(sessionID: UUID, transcript: String?, evidence: VoiceRecognitionEvidence?, isFinal: Bool, hasError: Bool, errorDomain: String, errorCode: Int) {
        guard owns(sessionID) else {
            LocalVoiceDiagnosticReport.shared.record("stale_recognition_suppressed", "final=\(isFinal) error_code=\(errorCode)")
            return
        }
        recognitionCallbackCount += 1
        if transcript != nil {
            if isFinal { finalResultCount += 1 } else { partialResultCount += 1 }
        }
        LocalVoiceDiagnosticReport.shared.record("recognition_callback", "count=\(recognitionCallbackCount) has_text=\(transcript != nil) final=\(isFinal) error_domain=\(errorDomain) error_code=\(errorCode) partial_count=\(partialResultCount) final_count=\(finalResultCount)")
        if let transcript {
            if let evidence {
                eventHandler?(.recognitionEvidence(evidence))
                let bucket = evidence.averageSegmentConfidence.map {
                    $0 >= 0.8 ? "high" : ($0 >= 0.5 ? "medium" : "low")
                } ?? "unavailable"
                LocalVoiceDiagnosticReport.shared.record(
                    "recognition_evidence",
                    "alternatives=\(evidence.alternativeTranscripts.count) segment_alternatives=\(evidence.segmentAlternativeCount) confidence_bucket=\(bucket)"
                )
            }
            self.transcript = transcript
            eventHandler?(.transcript(transcript, isFinal: isFinal))
            LocalVoiceDiagnosticReport.shared.recordSpeechTranscript(transcript, isFinal: isFinal)
            LocalVoiceDiagnosticReport.shared.record("transcript_delivered_to_ui", "length=\(transcript.count) final=\(isFinal)")
            if !isFinal, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                endOfSpeechFinalizer.receivedPartial { [weak self] in
                    self?.finishAfterEndOfSpeech(sessionID: sessionID)
                }
            }
        }
        if hasError { stop(reason: .recognitionError, ownedBy: sessionID) }
        else if isFinal {
            LocalVoiceDiagnosticReport.shared.record("recognition_task_finished", "reason=final_result")
            stop(reason: .recognitionFinal, ownedBy: sessionID)
        }
    }

    private func finishAfterEndOfSpeech(sessionID: UUID) {
        guard owns(sessionID), state == .listening, !isFinalizingRecognition,
              let request, let task else { return }
        isFinalizingRecognition = true
        requestSink?.deactivate()
        LocalVoiceDiagnosticReport.shared.record("end_audio_called", "reason=endOfSpeech had_request=true")
        request.endAudio()
        LocalVoiceDiagnosticReport.shared.record("recognition_task_finished", "reason=endOfSpeech")
        task.finish()
        capture.stop()
    }

    func handleAudioInterruptionBegan() {
        LocalVoiceDiagnosticReport.shared.record("audio_interruption", "state=began")
        stop(reason: .audioInterruption)
    }
    func handleAudioRouteChanged() {
        if state == .listening, !isFinalizingRecognition { stop(reason: .routeChange) }
    }

    func handleAudioRouteChanged(_ evidence: AudioRouteChangeEvidence) {
        LocalVoiceDiagnosticReport.shared.record("route_change", evidence.diagnosticDescription)
        if evidence.requiresVoiceCaptureStop {
            handleAudioRouteChanged()
        } else {
            LocalVoiceDiagnosticReport.shared.record("route_change_ignored", "reason=\(evidence.reasonName) input_preserved=true")
        }
    }

    nonisolated static func awaitSpeechAuthorization(
        _ request: @escaping @Sendable (@escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void) -> Void
    ) async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            request { status in continuation.resume(returning: status) }
        }
    }

    private nonisolated static func authorizationGranted() async -> Bool {
        LocalVoiceDiagnosticReport.shared.record("speech_permission_before", "state=\(String(describing: SFSpeechRecognizer.authorizationStatus()))")
        let speech = await awaitSpeechAuthorization { completion in
            SFSpeechRecognizer.requestAuthorization(completion)
        }
        LocalVoiceDiagnosticReport.shared.record("speech_permission_after", "state=\(String(describing: speech))")
        guard speech == .authorized else { return false }
        LocalVoiceDiagnosticReport.shared.record("microphone_permission_before", "state=\(String(describing: AVAudioApplication.shared.recordPermission))")
        let microphone = await AVAudioApplication.requestRecordPermission()
        LocalVoiceDiagnosticReport.shared.record("microphone_permission", "granted=\(microphone)")
        return microphone
    }

    private nonisolated static func makeRecognitionHandler(
        owner: VoiceInputController,
        sessionID: UUID
    ) -> @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { [weak owner] result, error in
            let transcript = result?.bestTranscription.formattedString
            let evidence = result.map { result in
                let segments = result.bestTranscription.segments
                let confidenceValues = segments.map { Double($0.confidence) }.filter { $0 > 0 }
                let average = confidenceValues.isEmpty ? nil :
                    confidenceValues.reduce(0, +) / Double(confidenceValues.count)
                return VoiceRecognitionEvidence(
                    primaryTranscript: result.bestTranscription.formattedString,
                    alternativeTranscripts: Array(result.transcriptions.dropFirst().prefix(4).map(\.formattedString)),
                    segmentAlternativeCount: segments.reduce(0) { $0 + $1.alternativeSubstrings.count },
                    averageSegmentConfidence: average
                )
            }
            let isFinal = result?.isFinal == true
            let hasError = error != nil
            let nsError = error as NSError?
            let errorDomain = nsError?.domain ?? "none"
            let errorCode = nsError?.code ?? 0
            Task { @MainActor [weak owner] in
                owner?.receiveRecognition(sessionID: sessionID, transcript: transcript, evidence: evidence, isFinal: isFinal, hasError: hasError, errorDomain: errorDomain, errorCode: errorCode)
            }
        }
    }

    private func owns(_ sessionID: UUID) -> Bool { activeSessionID == sessionID }
}
