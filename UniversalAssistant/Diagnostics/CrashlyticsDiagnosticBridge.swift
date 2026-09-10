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

protocol CrashlyticsDiagnosticRecording: Sendable {
    func beginRequest(_ identity: CrashlyticsDiagnosticRequestIdentity, inputMode: String)
    func recordEvent(
        _ marker: String,
        details: String,
        sequence: Int,
        identity: CrashlyticsDiagnosticRequestIdentity
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
    private var activeRequestID: UUID?
    private var activeInputMode = "unknown"
    private var terminalRequestOrder: [UUID] = []
    private var terminalRequestIDs: Set<UUID> = []
    private static let maximumRememberedTerminalRequests = 512
    private static let maximumCustomValueBytes = 900
    private static let maximumTranscriptLogBytes = 12_000
    private static let maximumEventLogBytes = 1_500

    private convenience init() {
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

    func beginRequest(_ identity: CrashlyticsDiagnosticRequestIdentity, inputMode: String) {
        guard isReady else { return }
        lock.lock()
        if activeRequestID != identity.requestID {
            activeRequestID = identity.requestID
            activeInputMode = inputMode
        } else if activeInputMode == "unknown", inputMode != "unknown" {
            activeInputMode = inputMode
        }
        let resolvedInputMode = activeInputMode
        lock.unlock()

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
        setIdentity(identity)
        updateInputMode(for: marker, identity: identity)
        setValue(marker, forKey: "ua_last_stage")
        setValue(sequence, forKey: "ua_event_sequence")

        let attributes = Self.parseAttributes(details)
        if marker == "selected_capability" || marker == "router_received" || marker == "router_accepted" {
            setValue(attributes["capability"] ?? "unknown", forKey: "ua_capability")
        }
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
        if marker == "execution_started" || marker.hasPrefix("EXECUTOR_") || marker.hasSuffix("_PRE") {
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

    func recordTranscript(
        _ transcript: String,
        normalized: Bool,
        sequence: Int,
        identity: CrashlyticsDiagnosticRequestIdentity,
        detailedDiagnosticsEnabled: Bool
    ) {
        guard isReady else { return }
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
        setValue(session.failureStage ?? "none", forKey: "ua_failure_stage")
        setValue(session.durationMilliseconds, forKey: "ua_elapsed_ms")
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
                "elapsed_ms": session.durationMilliseconds
            ]
        )
        client.record(error: error)
    }

    func recordRecoveredUncleanSession(_ session: PhysicalDiagnosticSession) {
        guard isReady else { return }
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
