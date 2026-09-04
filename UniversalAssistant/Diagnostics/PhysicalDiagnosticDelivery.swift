import CryptoKit
import DeviceCheck
import Foundation
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
    var id: UUID { sessionID }
}

enum PhysicalDiagnosticEnvironment {
    static func isInternalTestFlight(bundle: Bundle = .main) -> Bool {
        #if PRODUCTION
        return bundle.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
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
        guard let http = urlResponse as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw PhysicalDiagnosticDeliveryError.httpFailure }
        return try JSONDecoder.diagnostic.decode(Response.self, from: data)
    }
}

enum PhysicalDiagnosticDeliveryError: Error { case disabled, unsupported, invalidEndpoint, httpFailure, invalidChallenge }

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
    enum DeliveryState: String, Codable { case queued, sending, delivered, failedRetryable, expired }
    struct Queued: Codable { let session: PhysicalDiagnosticSession; var attempts: Int; let expiresAt: Date }

    private let attest: any AppAttestServicing
    private let transport: any DiagnosticHTTPTransport
    private let defaults: UserDefaults
    private let enabled: @Sendable () -> Bool
    private let queueKey = "internal-physical-diagnostics-v1"
    private let keyIDKey = "internal-app-attest-key-id"
    private let registrationKey = "internal-app-attest-registered"
    private var flushing = false
    private(set) var state: DeliveryState = .queued

    init(
        attest: any AppAttestServicing = SystemAppAttestService(),
        transport: any DiagnosticHTTPTransport = URLSessionDiagnosticTransport(baseURL: URL(string: "https://178.105.32.46")!),
        defaults: UserDefaults = .standard,
        enabled: @escaping @Sendable () -> Bool = { PhysicalDiagnosticEnvironment.isInternalTestFlight() }
    ) {
        self.attest = attest; self.transport = transport; self.defaults = defaults; self.enabled = enabled
    }

    func enqueue(_ session: PhysicalDiagnosticSession, now: Date = .now) async {
        guard enabled() else { return }
        var queue = load(now: now)
        if !queue.contains(where: { $0.session.sessionID == session.sessionID }) {
            queue.append(.init(session: session, attempts: 0, expiresAt: now.addingTimeInterval(86_400)))
            if queue.count > 20 { queue.removeFirst(queue.count - 20) }
            save(queue)
        }
        await flush(now: now)
    }

    func flush(now: Date = .now) async {
        guard enabled(), !flushing, attest.isSupported else { return }
        flushing = true; defer { flushing = false }
        var queue = load(now: now)
        guard !queue.isEmpty else { return }
        state = .sending
        do {
            let keyID = try await ensureAttestedKey()
            while let item = queue.first, item.attempts < 3 {
                let challenge: ChallengeResponse = try await transport.post("v1/app-attest/challenge", body: ChallengeRequest(operation: "diagnostic"), response: ChallengeResponse.self)
                let client = AssertionClientData(challengeID: challenge.challengeID, challenge: challenge.challenge, operation: "diagnostic", diagnostic: item.session)
                let clientData = try JSONEncoder.diagnostic.encode(client)
                let assertion = try await attest.generateAssertion(keyID, clientDataHash: Data(SHA256.hash(data: clientData)))
                let receipt: ReceiptResponse = try await transport.post("v1/diagnostics", body: AssertionEnvelope(keyID: keyID, assertion: assertion.base64EncodedString(), clientData: clientData.base64EncodedString()), response: ReceiptResponse.self)
                guard receipt.sessionID == item.session.sessionID, receipt.status == "delivered" else { throw PhysicalDiagnosticDeliveryError.httpFailure }
                queue.removeFirst(); save(queue); state = .delivered
            }
        } catch {
            if !queue.isEmpty { queue[0].attempts += 1; save(queue) }
            state = .failedRetryable
        }
    }

    func pendingCount(now: Date = .now) -> Int { load(now: now).count }
    func pendingAttempts(now: Date = .now) -> [Int] { load(now: now).map(\.attempts) }

    private func ensureAttestedKey() async throws -> String {
        guard attest.isSupported else { throw PhysicalDiagnosticDeliveryError.unsupported }
        if let key = defaults.string(forKey: keyIDKey), defaults.bool(forKey: registrationKey) { return key }
        let keyID: String
        if let existing = defaults.string(forKey: keyIDKey) { keyID = existing }
        else { keyID = try await attest.generateKey() }
        defaults.set(keyID, forKey: keyIDKey)
        let challenge: ChallengeResponse = try await transport.post("v1/app-attest/challenge", body: ChallengeRequest(operation: "attest"), response: ChallengeResponse.self)
        guard let challengeData = Data(base64Encoded: challenge.challenge) else { throw PhysicalDiagnosticDeliveryError.invalidChallenge }
        let attestation = try await attest.attestKey(keyID, clientDataHash: Data(SHA256.hash(data: challengeData)))
        let response = try await transport.post("v1/app-attest/register", body: RegistrationRequest(challengeID: challenge.challengeID, keyID: keyID, attestation: attestation.base64EncodedString()), response: RegistrationResponse.self)
        guard response.status == "registered" else { throw PhysicalDiagnosticDeliveryError.httpFailure }
        defaults.set(true, forKey: registrationKey)
        return keyID
    }

    private func load(now: Date) -> [Queued] {
        guard let data = defaults.data(forKey: queueKey), let decoded = try? JSONDecoder.diagnostic.decode([Queued].self, from: data) else { return [] }
        let active = decoded.filter { $0.expiresAt > now && $0.attempts < 3 }
        if active.count != decoded.count { save(active); state = .expired }
        return active
    }
    private func save(_ queue: [Queued]) { defaults.set(try? JSONEncoder.diagnostic.encode(queue), forKey: queueKey) }
}

extension JSONEncoder {
    static var diagnostic: JSONEncoder { let value = JSONEncoder(); value.outputFormatting = [.sortedKeys]; return value }
}
extension JSONDecoder { static var diagnostic: JSONDecoder { JSONDecoder() } }
