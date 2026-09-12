import CryptoKit
import FirebaseCore
import FirebaseCrashlytics
import Foundation

struct CrashlyticsDiagnosticRequestIdentity: Equatable, Sendable {
    let diagnosticSessionID: UUID
    let requestID: UUID
    let generation: UInt64
    let appVersion: String
    let build: Int
}

struct CrashlyticsRequestTraceSnapshot: Codable, Equatable, Sendable {
    let schema: Int
    let diagnosticSessionID: UUID
    let requestID: UUID
    let generation: UInt64
    let appVersion: String
    let build: Int
    let inputMode: String
    let partialTranscripts: [String]
    let finalTranscript: String?
    let normalizedTranscript: String?
    let audioRelativePath: String?
    let audioTruncated: Bool
    let events: [PhysicalDiagnosticEvent]
    let terminalState: String
    let result: String
    let failureStage: String?
    let traceTruncated: Bool
}

protocol CrashlyticsDiagnosticRecording: Sendable {
    func beginRequest(_ identity: CrashlyticsDiagnosticRequestIdentity, inputMode: String)
    func recordEvent(
        _ marker: String,
        details: String,
        sequence: Int,
        identity: CrashlyticsDiagnosticRequestIdentity
    )
    func recordPartialTranscript(
        _ transcript: String,
        sequence: Int,
        identity: CrashlyticsDiagnosticRequestIdentity,
        detailedDiagnosticsEnabled: Bool
    )
    func recordTranscript(
        _ transcript: String,
        normalized: Bool,
        sequence: Int,
        identity: CrashlyticsDiagnosticRequestIdentity,
        detailedDiagnosticsEnabled: Bool
    )
    func recordTerminal(_ session: PhysicalDiagnosticSession)
    func recordRecoveredUncleanSession(_ session: PhysicalDiagnosticSession)
    func recordMetricKitPayload(
        kind: String,
        fingerprint: String,
        payload: String,
        identity: CrashlyticsDiagnosticRequestIdentity
    )
}

protocol CrashlyticsClient: AnyObject {
    func setCustomValue(_ value: Any, forKey key: String)
    func log(_ message: String)
    func record(error: Error)
}

private final class FirebaseCrashlyticsClient: CrashlyticsClient {
    func setCustomValue(_ value: Any, forKey key: String) {
        Crashlytics.crashlytics().setCustomValue(value, forKey: key)
    }

    func log(_ message: String) {
        Crashlytics.crashlytics().log(message)
    }

    func record(error: Error) {
        Crashlytics.crashlytics().record(error: error)
    }
}

final class CrashlyticsDiagnosticBridge: CrashlyticsDiagnosticRecording, @unchecked Sendable {
    static let shared = CrashlyticsDiagnosticBridge()

    private let client: any CrashlyticsClient
    private let readiness: @Sendable () -> Bool
    private let lock = NSLock()
    private let clientWriteLock = NSRecursiveLock()
    private var activeRequestID: UUID?
    private var activeInputMode = "unknown"
    private var terminalRequestOrder: [UUID] = []
    private var terminalRequestIDs: Set<UUID> = []
    private static let maximumRememberedTerminalRequests = 512
    private static let maximumCustomValueBytes = 900
    private static let maximumTranscriptLogBytes = 12_000
    private static let maximumEventLogBytes = 1_500
    private static let maximumTraceChunks = 24
    private static let maximumTraceBytes = 15_000
    private static let requestScopedKeys = [
        "ua_transcript", "ua_transcript_length", "ua_transcript_sha256", "ua_transcript_truncated",
        "ua_normalized", "ua_normalized_length", "ua_normalized_sha256", "ua_normalized_truncated",
        "ua_capability", "ua_route", "ua_provider", "ua_executor", "ua_result",
        "ua_terminal_state", "ua_failure_stage", "ua_generic_web", "ua_fallback_reason",
        "ua_last_pre", "ua_last_post", "ua_elapsed_ms", "ua_event_sequence"
    ]


    convenience init() {
        self.init(client: FirebaseCrashlyticsClient(), readiness: { FirebaseApp.app() != nil })
    }

    init(client: any CrashlyticsClient, readiness: @escaping @Sendable () -> Bool) {
        self.client = client
        self.readiness = readiness
    }

    static func configureProductionCollection() {
        #if PRODUCTION
        FirebaseApp.configure()
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        shared.recordConnectivityProbeOncePerBuild()
        #endif
    }
    /// Used only by the targeted ingestion XCTest; production startup remains
    /// governed by configureProductionCollection().
    static func configureTargetedValidationCollection() {
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
    }


    func beginRequest(_ identity: CrashlyticsDiagnosticRequestIdentity, inputMode: String) {
        guard isReady else { return }
        clientWriteLock.lock()
        defer { clientWriteLock.unlock() }
        lock.lock()
        let isNewRequest = activeRequestID != identity.requestID
        if isNewRequest {
            activeRequestID = identity.requestID
            activeInputMode = inputMode
        } else if activeInputMode == "unknown", inputMode != "unknown" {
            activeInputMode = inputMode
        }
        let resolvedInputMode = activeInputMode
        lock.unlock()

        if isNewRequest { clearRequestSnapshot() }
        setIdentity(identity)
        setValue(resolvedInputMode, forKey: "ua_input_mode")
        setValue("request_created", forKey: "ua_last_stage")
        log("UA_TRACE marker=REQUEST_BEGIN input_mode=\(resolvedInputMode)", identity: identity, sequence: 0)
    }

    func recordEvent(
        _ marker: String,
        details: String,
        sequence: Int,
        identity: CrashlyticsDiagnosticRequestIdentity
    ) {
        guard isReady else { return }
        clientWriteLock.lock()
        defer { clientWriteLock.unlock() }
        setIdentity(identity)
        updateInputMode(for: marker, identity: identity)
        setValue(marker, forKey: "ua_last_stage")
        setValue(sequence, forKey: "ua_event_sequence")

        let attributes = Self.parseAttributes(details)
        if marker == "selected_capability" || marker == "router_received" || marker == "router_accepted" {
            setValue(attributes["capability"] ?? "unknown", forKey: "ua_capability")
        }
        if let route = attributes["route"] { setValue(route, forKey: "ua_route") }
        if let provider = attributes["provider"] { setValue(provider, forKey: "ua_provider") }
        if marker == "generic_web_selected" {
            setValue(attributes["selected"] ?? "unknown", forKey: "ua_generic_web")
            setValue(attributes["reason"] ?? "unknown", forKey: "ua_fallback_reason")
        }
        if marker.hasSuffix("_PRE") {
            setValue(marker, forKey: "ua_last_pre")
        }
        if marker.hasSuffix("_POST") {
            setValue(marker, forKey: "ua_last_post")
        }
        if marker == "execution_started"
            || marker.hasPrefix("EXECUTOR_")
            || marker.hasPrefix("PROVIDER_")
        {
            let mechanism = attributes["mechanism"] ?? attributes["provider"] ?? attributes["capability"] ?? marker
            setValue(mechanism, forKey: "ua_executor")
        }
        if marker == "visible_result" {
            setValue(attributes["kind"] ?? "visible", forKey: "ua_result")
        }
        if marker == "terminal_request_state" {
            setValue(attributes["state"] ?? "unknown", forKey: "ua_terminal_state")
        }

        let safeDetails = Self.bounded(Self.redactSecrets(details), maximumUTF8Bytes: Self.maximumEventLogBytes)
        log("UA_TRACE marker=\(marker) \(safeDetails)", identity: identity, sequence: sequence)
    }

    func recordPartialTranscript(
        _ transcript: String,
        sequence: Int,
        identity: CrashlyticsDiagnosticRequestIdentity,
        detailedDiagnosticsEnabled: Bool
    ) {
        guard isReady else { return }
        clientWriteLock.lock()
        defer { clientWriteLock.unlock() }
        setIdentity(identity)
        setValue("PARTIAL_TRANSCRIPT", forKey: "ua_last_stage")
        setValue(sequence, forKey: "ua_event_sequence")
        guard detailedDiagnosticsEnabled else {
            log("UA_TRACE marker=PARTIAL_TRANSCRIPT detailed=false original_length=\(transcript.count)", identity: identity, sequence: sequence)
            return
        }

        let redacted = Self.redactSecrets(transcript)
        let logValue = Self.bounded(redacted, maximumUTF8Bytes: Self.maximumTranscriptLogBytes)
        let keyValue = Self.bounded(redacted, maximumUTF8Bytes: Self.maximumCustomValueBytes)
        setValue(keyValue, forKey: "ua_partial_transcript")
        setValue(redacted.utf8.count, forKey: "ua_partial_transcript_length")
        log("UA_TRACE marker=PARTIAL_TRANSCRIPT text=\(Self.singleLine(logValue))", identity: identity, sequence: sequence)
    }

    func recordTranscript(
        _ transcript: String,
        normalized: Bool,
        sequence: Int,
        identity: CrashlyticsDiagnosticRequestIdentity,
        detailedDiagnosticsEnabled: Bool
    ) {
        guard isReady else { return }
        clientWriteLock.lock()
        defer { clientWriteLock.unlock() }
        setIdentity(identity)
        let marker = normalized ? "NORMALIZED_TRANSCRIPT" : "FINAL_SPEECH_TRANSCRIPT"
        setValue(marker, forKey: "ua_last_stage")
        setValue(sequence, forKey: "ua_event_sequence")
        guard detailedDiagnosticsEnabled else {
            log("UA_TRACE marker=\(marker) detailed=false original_length=\(transcript.count)", identity: identity, sequence: sequence)
            return
        }

        let redacted = Self.redactSecrets(transcript)
        let digest = Self.sha256(redacted)
        let logValue = Self.bounded(redacted, maximumUTF8Bytes: Self.maximumTranscriptLogBytes)
        let keyValue = Self.bounded(redacted, maximumUTF8Bytes: Self.maximumCustomValueBytes)
        let wasTruncated = logValue.utf8.count < redacted.utf8.count
        let prefix = normalized ? "ua_normalized" : "ua_transcript"

        setValue(keyValue, forKey: prefix)
        setValue(redacted.utf8.count, forKey: "\(prefix)_length")
        setValue(digest, forKey: "\(prefix)_sha256")
        setValue(wasTruncated, forKey: "\(prefix)_truncated")
        let truncation = wasTruncated
            ? " TRUNCATED_BY_PROVIDER_LIMIT original_length=\(redacted.utf8.count) sha256=\(digest)"
            : ""
        log("UA_TRACE marker=\(marker) text=\(Self.singleLine(logValue))\(truncation)", identity: identity, sequence: sequence)
    }

    func recordTerminal(_ session: PhysicalDiagnosticSession) {
        guard isReady, session.detailedDiagnosticsConsent == true else { return }
        let requestID = session.requestID ?? session.sessionID
        guard rememberTerminalRequest(requestID) else { return }
        clientWriteLock.lock()
        defer { clientWriteLock.unlock() }

        let identity = CrashlyticsDiagnosticRequestIdentity(
            diagnosticSessionID: session.diagnosticSessionID ?? session.sessionID,
            requestID: requestID,
            generation: session.requestGeneration ?? 0,
            appVersion: session.appVersion,
            build: session.build
        )
        setIdentity(identity)
        let terminal = session.terminalState?.rawValue ?? session.result.rawValue
        setValue(terminal, forKey: "ua_terminal_state")
        setValue(session.result.rawValue, forKey: "ua_result")
        setValue(session.failureStage ?? "none", forKey: "ua_failure_stage")
        setValue(session.durationMilliseconds, forKey: "ua_elapsed_ms")
        let traceMetadata = writeTraceSnapshot(session, identity: identity)
        log("UA_TRACE marker=TERMINAL_REQUEST_STATE state=\(terminal) elapsed_ms=\(session.durationMilliseconds)", identity: identity, sequence: session.events.count)

        let error = NSError(
            domain: "UA_DIAGNOSTIC_COMMAND_TRACE",
            code: Self.errorCode(for: session.terminalState),
            userInfo: [
                NSLocalizedDescriptionKey: "UniversalAssistant terminal production command trace",
                "request_id": requestID.uuidString,
                "terminal_state": terminal,
                "failure_stage": session.failureStage ?? "none",
                "event_count": session.events.count,
                "elapsed_ms": session.durationMilliseconds,
                "trace_sha256": traceMetadata.sha256,
                "trace_chunks": traceMetadata.chunkCount,
                "trace_truncated": traceMetadata.truncated
            ]
        )
        client.record(error: error)
    }

    func recordRecoveredUncleanSession(_ session: PhysicalDiagnosticSession) {
        guard isReady else { return }
        clientWriteLock.lock()
        defer { clientWriteLock.unlock() }
        let requestID = session.requestID ?? session.sessionID
        let identity = CrashlyticsDiagnosticRequestIdentity(
            diagnosticSessionID: session.diagnosticSessionID ?? session.sessionID,
            requestID: requestID,
            generation: session.requestGeneration ?? 0,
            appVersion: session.appVersion,
            build: session.build
        )
        setIdentity(identity)
        setValue("UNCLEAN_TERMINATION_DETECTED", forKey: "ua_last_stage")
        setValue(session.failureStage ?? "unknown", forKey: "ua_failure_stage")
        log(
            "UA_TRACE marker=UNCLEAN_TERMINATION_DETECTED probable_boundary=\(session.failureStage ?? "unknown")",
            identity: identity,
            sequence: session.events.count
        )
    }
    func recordMetricKitPayload(
        kind: String,
        fingerprint: String,
        payload: String,
        identity: CrashlyticsDiagnosticRequestIdentity
    ) {
        guard isReady else { return }
        clientWriteLock.lock()
        defer { clientWriteLock.unlock() }
        setIdentity(identity)
        setValue("METRICKIT_PAYLOAD_RECEIVED", forKey: "ua_last_stage")
        setValue(kind, forKey: "ua_metrickit_kind")
        setValue(fingerprint, forKey: "ua_metrickit_fingerprint")

        let safePayload = Self.redactSecrets(payload)
        let boundedPayload = Self.bounded(safePayload, maximumUTF8Bytes: Self.maximumTranscriptLogBytes)
        let truncation = boundedPayload.utf8.count < safePayload.utf8.count
            ? " TRUNCATED_BY_PROVIDER_LIMIT original_length=\(safePayload.utf8.count) sha256=\(fingerprint)"
            : ""
        log(
            "UA_TRACE marker=METRICKIT_PAYLOAD_RECEIVED kind=\(kind) payload=\(Self.singleLine(boundedPayload))\(truncation)",
            identity: identity,
            sequence: 0
        )
        client.record(
            error: NSError(
                domain: "UA_METRICKIT_PAYLOAD",
                code: kind == "diagnostic" ? 1 : 2,
                userInfo: [
                    NSLocalizedDescriptionKey: "Apple MetricKit payload received",
                    "kind": kind,
                    "fingerprint": fingerprint,
                    "request_id": identity.requestID.uuidString
                ]
            )
        )
    }

    private struct TraceMetadata {
        let sha256: String
        let chunkCount: Int
        let truncated: Bool
    }

    private func writeTraceSnapshot(
        _ session: PhysicalDiagnosticSession,
        identity: CrashlyticsDiagnosticRequestIdentity
    ) -> TraceMetadata {
        let terminal = session.terminalState?.rawValue ?? session.result.rawValue
        let noisyMarkers: Set<String> = [
            "audio_buffer_received", "buffer_appended", "recognition_callback",
            "transcript_delivered_to_ui"
        ]
        var seenNoisyMarkers: Set<String> = []
        var events = session.events.compactMap { source -> PhysicalDiagnosticEvent? in
            if noisyMarkers.contains(source.marker), !seenNoisyMarkers.insert(source.marker).inserted {
                return nil
            }
            var event = source
            if ["partial_transcript", "final_transcript", "normalization"].contains(event.marker) {
                event.textPayload = nil
            }
            return event
        }
        var partials = session.events
            .filter { $0.marker == "partial_transcript" }
            .compactMap(\.textPayload)
        var truncated = events.count != session.events.count
        var snapshot = makeTraceSnapshot(
            session: session,
            identity: identity,
            terminal: terminal,
            partials: partials,
            events: events,
            truncated: truncated
        )
        var data = (try? JSONEncoder().encode(snapshot)) ?? Data()
        let originalEncodedByteCount = data.count

        if data.count > Self.maximumTraceBytes {
            truncated = true
            partials = Array(partials.suffix(20))
            let criticalMarkers: Set<String> = [
                "request_created", "home_request_started", "mic_tap", "start_listening_invoked",
                "audio_session_activated", "SPEECH_START_PRE", "SPEECH_START_POST",
                "final_transcript", "normalization", "language_detection", "morphology",
                "structured_number_reconstruction", "entity_recovery", "canonical_semantic_frame",
                "candidate_capabilities", "selected_capability", "system_first_decision",
                "generic_web_selected", "current_context_input", "router_received", "router_accepted",
                "execution_started", "execution_failed", "visible_result",
                "terminal_request_state", "request_end"
            ]
            events = events.filter {
                criticalMarkers.contains($0.marker)
                    || $0.marker.hasSuffix("_PRE")
                    || $0.marker.hasSuffix("_POST")
            }
            snapshot = makeTraceSnapshot(
                session: session,
                identity: identity,
                terminal: terminal,
                partials: partials,
                events: events,
                truncated: true
            )
            data = (try? JSONEncoder().encode(snapshot)) ?? Data()
        }

        if data.count > Self.maximumTraceBytes {
            truncated = true
            events = Array(events.prefix(8)) + Array(events.suffix(16))
            snapshot = makeTraceSnapshot(
                session: session,
                identity: identity,
                terminal: terminal,
                partials: Array(partials.suffix(4)),
                events: events,
                truncated: true
            )
            data = (try? JSONEncoder().encode(snapshot)) ?? Data()
        }

        if data.count > Self.maximumTraceBytes {
            truncated = true
            events = Array(events.suffix(8))
            snapshot = makeTraceSnapshot(
                session: session,
                identity: identity,
                terminal: terminal,
                partials: Array(partials.suffix(2)),
                events: events,
                truncated: true
            )
            data = (try? JSONEncoder().encode(snapshot)) ?? Data()
        }

        if data.count > Self.maximumTraceBytes {
            truncated = true
            snapshot = makeTraceSnapshot(
                session: session,
                identity: identity,
                terminal: terminal,
                partials: [],
                events: [],
                truncated: true
            )
            data = (try? JSONEncoder().encode(snapshot)) ?? Data()
        }
        // The final compaction contains bounded transcript fields and no event
        // array, so this remains valid JSON instead of a byte-truncated blob.
        let boundedData = data

        let base64 = boundedData.base64EncodedString()
        let chunks = stride(from: 0, to: base64.count, by: Self.maximumCustomValueBytes).map { offset in
            let start = base64.index(base64.startIndex, offsetBy: offset)
            let end = base64.index(start, offsetBy: min(Self.maximumCustomValueBytes, base64.count - offset))
            return String(base64[start..<end])
        }
        let boundedChunks = Array(chunks.prefix(Self.maximumTraceChunks))
        let providerTruncated = boundedChunks.count != chunks.count || boundedData.count != data.count
        let digest = Self.sha256(String(decoding: data, as: UTF8.self))

        for index in 0..<Self.maximumTraceChunks {
            setValue(index < boundedChunks.count ? boundedChunks[index] : "", forKey: String(format: "ua_trace_%02d", index))
        }
        setValue(3, forKey: "ua_trace_schema")
        setValue("base64-json", forKey: "ua_trace_encoding")
        setValue(boundedChunks.count, forKey: "ua_trace_chunk_count")
        setValue(digest, forKey: "ua_trace_sha256")
        setValue(truncated || providerTruncated, forKey: "ua_trace_truncated")
        setValue(originalEncodedByteCount, forKey: "ua_trace_original_bytes")
        for (index, chunk) in boundedChunks.enumerated() {
            log(
                "UA_TRACE marker=REQUEST_TRACE_CHUNK index=\(index) count=\(boundedChunks.count) data=\(chunk)",
                identity: identity,
                sequence: session.events.count + index + 1
            )
        }
        if truncated || providerTruncated {
            log(
                "UA_TRACE marker=TRUNCATED_BY_PROVIDER_LIMIT original_length=\(originalEncodedByteCount) sha256=\(digest)",
                identity: identity,
                sequence: session.events.count + boundedChunks.count + 1
            )
        }
        return .init(sha256: digest, chunkCount: boundedChunks.count, truncated: truncated || providerTruncated)
    }

    private func makeTraceSnapshot(
        session: PhysicalDiagnosticSession,
        identity: CrashlyticsDiagnosticRequestIdentity,
        terminal: String,
        partials: [String],
        events: [PhysicalDiagnosticEvent],
        truncated: Bool
    ) -> CrashlyticsRequestTraceSnapshot {
        CrashlyticsRequestTraceSnapshot(
            schema: 3,
            diagnosticSessionID: identity.diagnosticSessionID,
            requestID: identity.requestID,
            generation: identity.generation,
            appVersion: identity.appVersion,
            build: identity.build,
            inputMode: session.feature == "voice" ? "voice" : "text",
            partialTranscripts: truncated
                ? partials.map { Self.bounded($0, maximumUTF8Bytes: 1_000) }
                : partials,
            finalTranscript: truncated
                ? session.finalSpeechTranscript.map { Self.bounded($0, maximumUTF8Bytes: 2_500) }
                : session.finalSpeechTranscript,
            normalizedTranscript: truncated
                ? session.normalizedTranscript.map { Self.bounded($0, maximumUTF8Bytes: 2_500) }
                : session.normalizedTranscript,
            audioRelativePath: session.diagnosticAudioRelativePath,
            audioTruncated: session.diagnosticAudioTruncated ?? false,
            events: events,
            terminalState: terminal,
            result: session.result.rawValue,
            failureStage: session.failureStage,
            traceTruncated: truncated
        )
    }

    private func clearRequestSnapshot() {
        for key in Self.requestScopedKeys { setValue("", forKey: key) }
        setValue("", forKey: "ua_partial_transcript")
        setValue("", forKey: "ua_partial_transcript_length")
        setValue("", forKey: "ua_trace_schema")
        setValue("", forKey: "ua_trace_encoding")
        setValue("", forKey: "ua_trace_chunk_count")
        setValue("", forKey: "ua_trace_sha256")
        setValue("", forKey: "ua_trace_truncated")
        setValue("", forKey: "ua_trace_original_bytes")
        for index in 0..<Self.maximumTraceChunks {
            setValue("", forKey: String(format: "ua_trace_%02d", index))
        }
    }


    private var isReady: Bool {
        readiness()
    }

    private func updateInputMode(for marker: String, identity: CrashlyticsDiagnosticRequestIdentity) {
        lock.lock()
        if activeRequestID != identity.requestID {
            activeRequestID = identity.requestID
            activeInputMode = "unknown"
        }
        if ["start_listening_invoked", "final_transcript", "transcript_delivered_to_router"].contains(marker) {
            activeInputMode = "voice"
        } else if marker == "home_request_started", activeInputMode == "unknown" {
            activeInputMode = "text"
        }
        let value = activeInputMode
        lock.unlock()
        setValue(value, forKey: "ua_input_mode")
    }

    private func rememberTerminalRequest(_ requestID: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard terminalRequestIDs.insert(requestID).inserted else { return false }
        terminalRequestOrder.append(requestID)
        if terminalRequestOrder.count > Self.maximumRememberedTerminalRequests {
            let expired = terminalRequestOrder.removeFirst()
            terminalRequestIDs.remove(expired)
        }
        return true
    }

    private func setIdentity(_ identity: CrashlyticsDiagnosticRequestIdentity) {
        setValue(identity.diagnosticSessionID.uuidString, forKey: "ua_diagnostic_session_id")
        setValue(identity.requestID.uuidString, forKey: "ua_request_id")
        setValue(identity.generation, forKey: "ua_request_generation")
        setValue(identity.appVersion, forKey: "ua_app_version")
        setValue(identity.build, forKey: "ua_build")
    }

    private func log(
        _ message: String,
        identity: CrashlyticsDiagnosticRequestIdentity,
        sequence: Int
    ) {
        let bounded = Self.bounded(message, maximumUTF8Bytes: Self.maximumEventLogBytes + Self.maximumTranscriptLogBytes)
        client.log("request_id=\(identity.requestID.uuidString) sequence=\(sequence) \(bounded)")
    }

    private func setValue(_ value: Any, forKey key: String) {
        client.setCustomValue(value, forKey: key)
    }

    private func recordConnectivityProbeOncePerBuild() {
        guard isReady else { return }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let defaultsKey = "firebase-crashlytics-connectivity-probe-\(version)-\(build)"
        guard !UserDefaults.standard.bool(forKey: defaultsKey) else { return }

        setValue(version, forKey: "ua_app_version")
        setValue(build, forKey: "ua_build")
        setValue("integration_probe", forKey: "ua_last_stage")
        client.log("UA_TRACE marker=FIREBASE_CONNECTIVITY_PROBE version=\(version) build=\(build)")
        client.record(
            error: NSError(
                domain: "UA_CRASHLYTICS_CONNECTIVITY_PROBE",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "UniversalAssistant Crashlytics connectivity probe"]
            )
        )
        UserDefaults.standard.set(true, forKey: defaultsKey)
    }

    private static func parseAttributes(_ details: String) -> [String: String] {
        Dictionary(uniqueKeysWithValues: details.split(separator: " ").compactMap { token in
            let pair = token.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { return nil }
            return (pair[0], pair[1])
        })
    }

    static func redactSecrets(_ input: String) -> String {
        var value = input.precomposedStringWithCanonicalMapping
        let replacements: [(String, String)] = [
            (#"(?i)\b(?:password|passwd|пароль|api[_ -]?key|client[_ -]?secret|access[_ -]?token|refresh[_ -]?token|bearer|authorization)\b\s*[:=]?\s*\S+"#, "[SECRET_REDACTED]"),
            (#"(?i)\bAIza[0-9A-Za-z_-]{20,}\b"#, "[API_KEY_REDACTED]"),
            (#"(?i)\beyJ[0-9A-Za-z_-]+\.[0-9A-Za-z_-]+\.[0-9A-Za-z_-]+\b"#, "[TOKEN_REDACTED]"),
            (#"(?i)https://[^/\s:@]+:[^@\s/]+@"#, "https://[CREDENTIAL_REDACTED]@")
        ]
        for (pattern, replacement) in replacements {
            value = value.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return value
    }

    static func bounded(_ value: String, maximumUTF8Bytes: Int) -> String {
        guard value.utf8.count > maximumUTF8Bytes else { return value }
        var bytes = 0
        var result = ""
        result.reserveCapacity(min(value.count, maximumUTF8Bytes))
        for character in value {
            let count = String(character).utf8.count
            guard bytes + count <= maximumUTF8Bytes else { break }
            result.append(character)
            bytes += count
        }
        return result
    }

    private static func singleLine(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func errorCode(for state: DiagnosticTerminalState?) -> Int {
        guard let state else { return 99 }
        return (DiagnosticTerminalState.allCases.firstIndex(of: state) ?? 98) + 1
    }
}
