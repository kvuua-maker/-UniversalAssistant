import CryptoKit
import Foundation
import MetricKit

/// Extends the existing physical-diagnostics delivery path with Apple's public
/// crash/hang diagnostic payloads. It deliberately avoids signal handlers: the
/// command breadcrumbs are durable before a failure and MetricKit supplies the
/// confirmed Apple diagnostic later.
final class PhysicalMetricKitDiagnostics: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = PhysicalMetricKitDiagnostics()

    private let lock = NSLock()
    private var started = false
    private var launchCorrelation: DiagnosticActiveRequestSnapshot?
    private let localStore: PhysicalDiagnosticLocalStore
    private let delivery: PhysicalDiagnosticDelivery
    private let crashlyticsRecorder: any CrashlyticsDiagnosticRecording
    private let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
    private let deviceClass: String = {
        #if targetEnvironment(simulator)
        return "iOS Simulator"
        #else
        return "iOS Device"
        #endif
    }()

    init(
        localStore: PhysicalDiagnosticLocalStore = .shared,
        delivery: PhysicalDiagnosticDelivery = .shared,
        crashlyticsRecorder: any CrashlyticsDiagnosticRecording = CrashlyticsDiagnosticBridge.shared
    ) {
        self.localStore = localStore
        self.delivery = delivery
        self.crashlyticsRecorder = crashlyticsRecorder
        super.init()
    }

    func start() {
        let shouldStart = lock.withLock { () -> Bool in
            guard !started else { return false }
            started = true
            launchCorrelation = localStore.activeSnapshot()
            return true
        }
        guard shouldStart else { return }
        MXMetricManager.shared.add(self)
        processDiagnostics(MXMetricManager.shared.pastDiagnosticPayloads)
        processMetrics(MXMetricManager.shared.pastPayloads)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        processDiagnostics(payloads)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        processMetrics(payloads)
    }

    private func processDiagnostics(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            process(payload.jsonRepresentation(), kind: "diagnostic", probableFailure: true)
        }
    }

    private func processMetrics(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            process(payload.jsonRepresentation(), kind: "metric", probableFailure: false)
        }
    }

    private func process(_ data: Data, kind: String, probableFailure: Bool) {
        guard let json = Self.privacySafeJSON(data) else { return }
        let fingerprint = SHA256.hash(data: Data(json.utf8)).map { String(format: "%02x", $0) }.joined()
        guard localStore.addAppleDiagnostic(json: json, fingerprint: fingerprint) else { return }
        let reportID = UUID()
        let correlation = lock.withLock { launchCorrelation }
        let now = Date()
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
        let identity = CrashlyticsDiagnosticRequestIdentity(
            diagnosticSessionID: correlation?.diagnosticSessionID ?? reportID,
            requestID: correlation?.requestID ?? reportID,
            generation: correlation?.requestGeneration ?? 0,
            appVersion: appVersion,
            build: build
        )
        var event = PhysicalDiagnosticEvent(
            sequence: 1,
            timestamp: now,
            marker: probableFailure ? "apple_diagnostic_received" : "apple_metric_received",
            attributes: ["kind": kind, "count": "1", "fingerprint": fingerprint]
        )
        event.diagnosticSessionID = identity.diagnosticSessionID
        event.requestID = identity.requestID
        event.requestGeneration = identity.generation
        event.build = build
        var session = PhysicalDiagnosticSession(
            schema: 2,
            sessionID: reportID,
            liveTestID: "BUILD32-PRODUCTION-BLACK-BOX",
            feature: probableFailure ? "apple_diagnostic" : "apple_metric",
            appVersion: appVersion,
            build: build,
            environment: "internal-testflight",
            osVersion: osVersion,
            deviceClass: deviceClass,
            startedAt: now,
            endedAt: now,
            durationMilliseconds: 0,
            result: probableFailure ? .crashSuspected : .success,
            failureStage: probableFailure ? correlation?.lastPRE ?? correlation?.lastStage : nil,
            errorDomain: probableFailure ? "MetricKitDiagnostic" : "MetricKitMetric",
            errorCode: nil,
            events: [event]
        )
        session.diagnosticSessionID = identity.diagnosticSessionID
        session.requestID = identity.requestID
        session.requestGeneration = identity.generation
        session.terminalState = probableFailure ? .error : .success
        session.detailedDiagnosticsConsent = false
        session.appleDiagnosticJSON = json
        if probableFailure, let correlation {
            session.anomaly = DiagnosticAnomalyAnalyzer.analyze(events: [event], active: correlation)
        }
        crashlyticsRecorder.recordMetricKitPayload(
            kind: kind,
            fingerprint: fingerprint,
            payload: json,
            identity: identity
        )
        Task { await delivery.enqueue(session) }
    }

    /// MetricKit contains stack symbols and process telemetry, but diagnostics
    /// must not carry user paths, URLs, account identifiers, or arbitrary long
    /// strings. This recursive filter preserves stack-tree evidence while
    /// redacting fields likely to contain personal payloads.
    static func privacySafeJSON(_ data: Data) -> String? {
        guard data.count <= 512_000,
              let object = try? JSONSerialization.jsonObject(with: data),
              let sanitized = sanitize(object),
              JSONSerialization.isValidJSONObject(sanitized),
              let bounded = try? JSONSerialization.data(withJSONObject: sanitized, options: [.sortedKeys]),
              bounded.count <= 60_000 else { return nil }
        return String(data: bounded, encoding: .utf8)
    }

    private static func sanitize(_ value: Any, key: String = "") -> Any? {
        let lowerKey = key.lowercased()
        if ["url", "path", "username", "email", "phone", "location", "address", "token", "secret"]
            .contains(where: lowerKey.contains) {
            return "[REDACTED]"
        }
        switch value {
        case let dictionary as [String: Any]:
            return dictionary.reduce(into: [String: Any]()) { output, item in
                output[item.key] = sanitize(item.value, key: item.key)
            }
        case let array as [Any]:
            return Array(array.prefix(1_000)).compactMap { sanitize($0, key: key) }
        case let string as String:
            return String(string.prefix(512))
        case is NSNumber, is NSNull:
            return value
        default:
            return nil
        }
    }
}
