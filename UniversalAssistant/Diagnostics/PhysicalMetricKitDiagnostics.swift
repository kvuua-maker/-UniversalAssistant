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
        delivery: PhysicalDiagnosticDelivery = .shared
    ) {
        self.localStore = localStore
        self.delivery = delivery
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
        process(MXMetricManager.shared.pastDiagnosticPayloads)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        process(payloads)
    }

    private func process(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            guard let json = Self.privacySafeJSON(payload.jsonRepresentation()) else { continue }
            let fingerprint = SHA256.hash(data: Data(json.utf8)).map { String(format: "%02x", $0) }.joined()
            guard localStore.addAppleDiagnostic(json: json, fingerprint: fingerprint) else { continue }
            let reportID = UUID()
            let correlation = lock.withLock { launchCorrelation }
            let now = Date()
            var event = PhysicalDiagnosticEvent(
                sequence: 1,
                timestamp: now,
                marker: "apple_diagnostic_received",
                attributes: ["kind": "MetricKit", "count": "1"]
            )
            event.diagnosticSessionID = correlation?.diagnosticSessionID ?? reportID
            event.requestID = correlation?.requestID ?? reportID
            event.requestGeneration = correlation?.requestGeneration ?? 0
            event.build = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
            var session = PhysicalDiagnosticSession(
                schema: 2,
                sessionID: reportID,
                liveTestID: "BUILD32-PRODUCTION-BLACK-BOX",
                feature: "apple_diagnostic",
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                build: Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0,
                environment: "internal-testflight",
                osVersion: osVersion,
                deviceClass: deviceClass,
                startedAt: now,
                endedAt: now,
                durationMilliseconds: 0,
                result: .crashSuspected,
                failureStage: correlation?.lastPRE ?? correlation?.lastStage,
                errorDomain: "MetricKit",
                errorCode: nil,
                events: [event]
            )
            session.diagnosticSessionID = correlation?.diagnosticSessionID ?? reportID
            session.requestID = correlation?.requestID ?? reportID
            session.requestGeneration = correlation?.requestGeneration ?? 0
            session.terminalState = .error
            session.detailedDiagnosticsConsent = false
            session.appleDiagnosticJSON = json
            if let correlation {
                session.anomaly = DiagnosticAnomalyAnalyzer.analyze(events: [event], active: correlation)
            }
            Task { await delivery.enqueue(session) }
        }
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
