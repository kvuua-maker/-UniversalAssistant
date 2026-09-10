import CryptoKit
import DeviceCheck
import Foundation
import StoreKit
import UIKit

enum PhysicalDiagnosticResult: String, Codable, Sendable {
    case success = "SUCCESS", failure = "FAILURE", crashSuspected = "CRASH_SUSPECTED"
    case interrupted = "INTERRUPTED", unknown = "UNKNOWN"
}

struct PhysicalDiagnosticEvent: Codable, Equatable, Sendable {
    let sequence: Int
    let timestamp: Date
    let marker: String
    let attributes: [String: String]
    // Schema-v2 request identity is repeated on every durable event so a
    // partially written ring buffer remains independently correlatable after
    // process death, before the enclosing upload session is assembled.
    var diagnosticSessionID: UUID? = nil
    var requestID: UUID? = nil
    var requestGeneration: UInt64? = nil
    var build: Int? = nil
}

struct PhysicalDiagnosticSession: Codable, Equatable, Sendable, Identifiable {
    let schema: Int
    let sessionID: UUID
    let liveTestID: String
    let feature: String
    let appVersion: String
    let build: Int
    let environment: String
    let osVersion: String
    let deviceClass: String
    let startedAt: Date
    let endedAt: Date
    let durationMilliseconds: Int
    let result: PhysicalDiagnosticResult
    let failureStage: String?
    let errorDomain: String?
    let errorCode: Int?
    let events: [PhysicalDiagnosticEvent]
    // Schema-v2 fields are optional so persisted schema-v1 sessions remain
    // decodable and uploadable during the Build-32 migration.
    var diagnosticSessionID: UUID? = nil
    var requestID: UUID? = nil
    var requestGeneration: UInt64? = nil
    var terminalState: DiagnosticTerminalState? = nil
    var detailedDiagnosticsConsent: Bool? = nil
    var finalSpeechTranscript: String? = nil
    var normalizedTranscript: String? = nil
    var anomaly: DiagnosticAnomaly? = nil
    var appleDiagnosticJSON: String? = nil
    var id: UUID { sessionID }
}

enum PhysicalDiagnosticEnvironment {
    static func isInternalTestFlight() async -> Bool {
        #if PRODUCTION
        do {
            switch try await AppTransaction.shared {
            case let .verified(transaction):
                return transaction.environment == .sandbox
            case .unverified:
                return false
            }
        } catch {
            return false
        }
        #else
        return false
        #endif
    }
}

protocol AppAttestServicing: Sendable {
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data
}

struct SystemAppAttestService: AppAttestServicing {
    var isSupported: Bool { DCAppAttestService.shared.isSupported }
    func generateKey() async throws -> String { try await DCAppAttestService.shared.generateKey() }
    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.attestKey(keyID, clientDataHash: clientDataHash)
    }
    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.generateAssertion(keyID, clientDataHash: clientDataHash)
    }
}

protocol DiagnosticHTTPTransport: Sendable {
    func post<Request: Encodable, Response: Decodable>(_ path: String, body: Request, response: Response.Type) async throws -> Response
}

struct URLSessionDiagnosticTransport: DiagnosticHTTPTransport {
    let baseURL: URL
    func post<Request: Encodable, Response: Decodable>(_ path: String, body: Request, response: Response.Type) async throws -> Response {
        let destination = baseURL.appending(path: path)
        guard destination.scheme == "https", destination.host == "178.105.32.46" else { throw PhysicalDiagnosticDeliveryError.invalidEndpoint }
        var request = URLRequest(url: destination, timeoutInterval: 12)
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.diagnostic.encode(body)
        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        guard let http = urlResponse as? HTTPURLResponse else { throw PhysicalDiagnosticDeliveryError.httpFailure(statusCode: 0) }
        guard (200..<300).contains(http.statusCode) else { throw PhysicalDiagnosticDeliveryError.httpFailure(statusCode: http.statusCode) }
        return try JSONDecoder.serverDiagnosticResponse.decode(Response.self, from: data)
    }
}

enum PhysicalDiagnosticDeliveryError: Error {
    case disabled, unsupported, invalidEndpoint, invalidChallenge, keyPersistenceFailed
    case httpFailure(statusCode: Int)
}

private struct AppAttestBootstrapEvent: Codable, Equatable, Sendable {
    let sequence: Int
    let marker: String
    let attributes: [String: String]
}
private struct AppAttestBootstrapFailureReport: Codable, Sendable {
    let schema: Int
    let reportID: UUID
    let appVersion: String
    let build: Int
    let environment: String
    let osVersion: String
    let deviceClass: String
    let startedAt: Date
    let endedAt: Date
    let failureStage: String
    let errorDomain: String
    let errorCode: Int
    let events: [AppAttestBootstrapEvent]
}
private struct BootstrapReceiptResponse: Codable { let reportID: UUID; let status: String; let receivedAt: Date }
private struct AppAttestBootstrapTrace: Sendable {
    let reportID = UUID()
    let startedAt = Date()
    private(set) var events: [AppAttestBootstrapEvent] = []

    mutating func record(_ marker: String, _ attributes: [String: String] = [:]) {
        events.append(.init(sequence: events.count + 1, marker: marker, attributes: attributes))
    }
}

private struct ChallengeRequest: Codable { let operation: String }
private struct ChallengeResponse: Codable { let challengeID: UUID; let challenge: String; let expiresAt: Date }
private struct RegistrationRequest: Codable { let challengeID: UUID; let keyID: String; let attestation: String }
private struct RegistrationResponse: Codable { let status: String }
private struct AssertionEnvelope: Codable { let keyID: String; let assertion: String; let clientData: String }
private struct AssertionClientData: Codable {
    let challengeID: UUID; let challenge: String; let operation: String; let diagnostic: PhysicalDiagnosticSession
}
private struct ReceiptResponse: Codable { let sessionID: UUID; let status: String; let receivedAt: Date }

actor PhysicalDiagnosticDelivery {
    static let shared = PhysicalDiagnosticDelivery()
    enum DeliveryState: String, Codable { case queued, sending, delivered, failedRetryable, serverRejected, expired }
    private struct LegacyQueued: Codable { let session: PhysicalDiagnosticSession; var attempts: Int; let expiresAt: Date }

    private let attest: any AppAttestServicing
    private let transport: any DiagnosticHTTPTransport
    private let defaults: UserDefaults
    private let localStore: PhysicalDiagnosticLocalStore
    private let enabled: @Sendable () async -> Bool
    private let queueKey = "internal-physical-diagnostics-v1"
    private let keyIDKey = "internal-app-attest-key-id"
    private let registrationKey = "internal-app-attest-registered"
    private var flushing = false
    private var retryTask: Task<Void, Never>?
    private(set) var state: DeliveryState = .queued

    init(
        attest: any AppAttestServicing = SystemAppAttestService(),
        transport: any DiagnosticHTTPTransport = URLSessionDiagnosticTransport(baseURL: URL(string: "https://178.105.32.46")!),
        defaults: UserDefaults = .standard,
        localStore: PhysicalDiagnosticLocalStore = .shared,
        enabled: @escaping @Sendable () async -> Bool = { await PhysicalDiagnosticEnvironment.isInternalTestFlight() }
    ) {
        self.attest = attest; self.transport = transport; self.defaults = defaults; self.localStore = localStore; self.enabled = enabled
        if let data = defaults.data(forKey: queueKey),
           let legacy = try? JSONDecoder.diagnostic.decode([LegacyQueued].self, from: data) {
            for item in legacy {
                localStore.addPending(.init(session: item.session, attempts: item.attempts, expiresAt: item.expiresAt,
                                            nextAttemptAt: .distantPast, status: .pendingUpload,
                                            lastHTTPStatus: nil, errorCategory: "migrated_schema_v1"))
            }
            defaults.removeObject(forKey: queueKey)
        }
    }

    func enqueue(_ session: PhysicalDiagnosticSession, now: Date = .now) async {
        localStore.addPending(.init(session: session, attempts: 0, expiresAt: now.addingTimeInterval(7 * 86_400),
                                    nextAttemptAt: now, status: .pendingUpload,
                                    lastHTTPStatus: nil, errorCategory: nil))
        // Local durability is unconditional. Environment/App Attest gates only
        // network delivery, never the on-device black box.
        guard await enabled() else { return }
        await flush(now: now)
    }

    func flush(now: Date = .now) async {
        guard await enabled(), !flushing else { return }
        flushing = true; defer { flushing = false }
        var queue = localStore.loadPending(now: now)
        guard !queue.isEmpty else { return }
        guard queue.contains(where: { $0.nextAttemptAt <= now && $0.status != .serverRejected }) else {
            state = .failedRetryable
            localStore.setDeliveryStatus(.retrying)
            scheduleRetry(for: queue, now: now)
            return
        }
        state = .sending
        localStore.setDeliveryStatus(.retrying)
        do {
            let keyID = try await ensureAttestedKey()
            while let index = queue.firstIndex(where: { $0.nextAttemptAt <= now && $0.status != .serverRejected }) {
                let item = queue[index]
                let challenge: ChallengeResponse = try await transport.post("v1/app-attest/challenge", body: ChallengeRequest(operation: "diagnostic"), response: ChallengeResponse.self)
                let client = AssertionClientData(challengeID: challenge.challengeID, challenge: challenge.challenge, operation: "diagnostic", diagnostic: item.session)
                let clientData = try JSONEncoder.diagnostic.encode(client)
                let assertion = try await attest.generateAssertion(keyID, clientDataHash: Data(SHA256.hash(data: clientData)))
                let receipt: ReceiptResponse = try await transport.post("v1/diagnostics", body: AssertionEnvelope(keyID: keyID, assertion: assertion.base64EncodedString(), clientData: clientData.base64EncodedString()), response: ReceiptResponse.self)
                guard receipt.sessionID == item.session.sessionID, receipt.status == "delivered" else { throw PhysicalDiagnosticDeliveryError.httpFailure(statusCode: 0) }
                queue.remove(at: index)
                localStore.savePending(queue)
                localStore.addReceipt(.init(sessionID: receipt.sessionID, uploadedAt: receipt.receivedAt, eventCount: item.session.events.count))
                state = .delivered
            }
            scheduleRetry(for: queue, now: now)
        } catch {
            guard let index = queue.firstIndex(where: { $0.nextAttemptAt <= now && $0.status != .serverRejected }) else { return }
            queue[index].attempts += 1
            if case let PhysicalDiagnosticDeliveryError.httpFailure(statusCode) = error,
               (400..<500).contains(statusCode), statusCode != 408, statusCode != 429 {
                queue[index].status = .serverRejected
                queue[index].lastHTTPStatus = statusCode
                queue[index].errorCategory = "server_rejected"
                queue[index].nextAttemptAt = queue[index].expiresAt
                state = .serverRejected
                localStore.setDeliveryStatus(.serverRejected)
            } else {
                let delay = min(900.0, pow(2.0, Double(min(queue[index].attempts, 9))))
                queue[index].status = .retrying
                queue[index].errorCategory = String(describing: type(of: error))
                queue[index].nextAttemptAt = now.addingTimeInterval(delay)
                state = .failedRetryable
                localStore.setDeliveryStatus(.retrying)
            }
            localStore.savePending(queue)
            scheduleRetry(for: queue, now: now)
        }
    }

    func pendingCount(now: Date = .now) -> Int { localStore.loadPending(now: now).count }
    func pendingAttempts(now: Date = .now) -> [Int] { localStore.loadPending(now: now).map(\.attempts) }

    private func scheduleRetry(for queue: [DiagnosticQueuedUpload], now: Date) {
        retryTask?.cancel()
        guard let next = queue
            .filter({ $0.status != .serverRejected && $0.expiresAt > now })
            .map(\.nextAttemptAt).min() else {
            retryTask = nil
            return
        }
        let delay = max(0.25, min(900, next.timeIntervalSince(now)))
        retryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) }
            catch { return }
            guard let self else { return }
            await self.flush()
        }
    }

    private func ensureAttestedKey() async throws -> String {
        var trace = AppAttestBootstrapTrace()
        trace.record("environment", ["value": "production"])
        trace.record("is_supported", ["value": String(attest.isSupported)])
        guard attest.isSupported else {
            let error = PhysicalDiagnosticDeliveryError.unsupported
            await sendBootstrapFailure(trace: trace, stage: "is_supported", error: error)
            throw error
        }
        if let key = defaults.string(forKey: keyIDKey), defaults.bool(forKey: registrationKey) { return key }
        let keyID: String
        do {
            if let existing = defaults.string(forKey: keyIDKey) {
                keyID = existing
                trace.record("key_id_loaded")
            } else {
                trace.record("generate_key_invoked")
                keyID = try await attest.generateKey()
                trace.record("generate_key_succeeded")
            }
            defaults.set(keyID, forKey: keyIDKey)
            guard defaults.string(forKey: keyIDKey) == keyID else { throw PhysicalDiagnosticDeliveryError.keyPersistenceFailed }
            trace.record("key_id_persisted")
            let challenge: ChallengeResponse = try await transport.post("v1/app-attest/challenge", body: ChallengeRequest(operation: "attest"), response: ChallengeResponse.self)
            let correlation = String(SHA256.hash(data: Data(challenge.challengeID.uuidString.utf8)).compactMap { String(format: "%02x", $0) }.joined().prefix(16))
            trace.record("challenge_received", ["correlation": correlation])
            guard let challengeData = Data(base64Encoded: challenge.challenge) else { throw PhysicalDiagnosticDeliveryError.invalidChallenge }
            trace.record("attest_key_invoked")
            let attestation = try await attest.attestKey(keyID, clientDataHash: Data(SHA256.hash(data: challengeData)))
            trace.record("attest_key_succeeded")
            trace.record("registration_request_constructed")
            trace.record("registration_request_attempted")
            let response = try await transport.post("v1/app-attest/register", body: RegistrationRequest(challengeID: challenge.challengeID, keyID: keyID, attestation: attestation.base64EncodedString()), response: RegistrationResponse.self)
            guard response.status == "registered" else { throw PhysicalDiagnosticDeliveryError.httpFailure(statusCode: 0) }
            trace.record("registration_succeeded")
            defaults.set(true, forKey: registrationKey)
            return keyID
        } catch {
            let stage = trace.events.last?.marker ?? "bootstrap_started"
            await sendBootstrapFailure(trace: trace, stage: stage, error: error)
            throw error
        }
    }

    private func sendBootstrapFailure(trace: AppAttestBootstrapTrace, stage: String, error: Error) async {
        let nsError = error as NSError
        var completed = trace
        if case let PhysicalDiagnosticDeliveryError.httpFailure(statusCode) = error {
            completed.record("http_result", ["stage": stage, "http_status": String(statusCode)])
        }
        completed.record("bootstrap_failed", ["stage": stage, "error_domain": nsError.domain, "error_code": String(nsError.code)])
        let device = await MainActor.run { (UIDevice.current.systemVersion, UIDevice.current.model) }
        let report = AppAttestBootstrapFailureReport(
            schema: 1, reportID: completed.reportID,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            build: Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0,
            environment: "internal-testflight", osVersion: device.0, deviceClass: device.1,
            startedAt: completed.startedAt, endedAt: .now, failureStage: stage,
            errorDomain: String(nsError.domain.prefix(128)), errorCode: nsError.code, events: completed.events)
        do {
            let receipt: BootstrapReceiptResponse = try await transport.post("v1/app-attest/bootstrap-failure", body: report, response: BootstrapReceiptResponse.self)
            guard receipt.reportID == report.reportID, receipt.status == "stored-unverified-bootstrap" else { return }
        } catch { }
    }

}

extension JSONEncoder {
    static var diagnostic: JSONEncoder { let value = JSONEncoder(); value.outputFormatting = [.sortedKeys]; return value }
}
extension JSONDecoder {
    static var diagnostic: JSONDecoder { JSONDecoder() }
    static var serverDiagnosticResponse: JSONDecoder {
        let value = JSONDecoder(); value.dateDecodingStrategy = .iso8601; return value
    }
}
