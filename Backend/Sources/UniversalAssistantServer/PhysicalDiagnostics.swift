import AppAttest
import Crypto
import Foundation
import Vapor

enum DiagnosticResult: String, Codable, Sendable {
    case success = "SUCCESS"
    case failure = "FAILURE"
    case crashSuspected = "CRASH_SUSPECTED"
    case interrupted = "INTERRUPTED"
    case unknown = "UNKNOWN"
}

struct DiagnosticEvent: Content, Codable, Equatable, Sendable {
    let sequence: Int
    let timestamp: Date
    let marker: String
    let attributes: [String: String]
}

struct PhysicalDiagnosticSession: Content, Codable, Equatable, Sendable {
    static let schemaVersion = 1
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
    let result: DiagnosticResult
    let failureStage: String?
    let errorDomain: String?
    let errorCode: Int?
    let events: [DiagnosticEvent]
}

struct ChallengeRequest: Content { let operation: String }
struct ChallengeResponse: Content { let challengeID: UUID; let challenge: String; let expiresAt: Date }
struct AttestationRegistrationRequest: Content { let challengeID: UUID; let keyID: String; let attestation: String }
struct AttestationRegistrationResponse: Content { let status: String }
struct AssertionEnvelope: Content { let keyID: String; let assertion: String; let clientData: String }
struct DiagnosticAssertionClientData: Codable, Equatable, Sendable {
    let challengeID: UUID
    let challenge: String
    let operation: String
    let diagnostic: PhysicalDiagnosticSession
}
struct ReceiptResponse: Content { let sessionID: UUID; let status: String; let receivedAt: Date }
struct AppAttestBootstrapEvent: Content, Codable, Equatable, Sendable {
    let sequence: Int
    let marker: String
    let attributes: [String: String]
}
struct AppAttestBootstrapFailureReport: Content, Codable, Equatable, Sendable {
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
struct BootstrapReceiptResponse: Content { let reportID: UUID; let status: String; let receivedAt: Date }

enum DiagnosticServerError: Error {
    case invalidConfiguration, invalidSchema, forbiddenField, invalidChallenge, invalidAttestation
    case invalidAssertion, replay, duplicateConflict, payloadTooLarge
}

actor ChallengeStore {
    struct Entry: Codable { let value: Data; let operation: String; let expiresAt: Date }
    private var entries: [UUID: Entry] = [:]
    private let lifetime: TimeInterval
    init(lifetime: TimeInterval = 300) { self.lifetime = lifetime }

    func issue(operation: String, now: Date = .now) throws -> (UUID, Entry) {
        guard ["attest", "diagnostic"].contains(operation) else { throw DiagnosticServerError.invalidChallenge }
        entries = entries.filter { $0.value.expiresAt > now }
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        let id = UUID()
        let entry = Entry(value: Data(bytes), operation: operation, expiresAt: now.addingTimeInterval(lifetime))
        entries[id] = entry
        return (id, entry)
    }

    func consume(id: UUID, operation: String, now: Date = .now) throws -> Entry {
        guard let entry = entries.removeValue(forKey: id), entry.expiresAt > now, entry.operation == operation else {
            throw DiagnosticServerError.invalidChallenge
        }
        return entry
    }
}

actor AppAttestRegistrationStore {
    struct Record: Codable {
        let keyID: String
        let publicKey: Data
        var counter: Int
        let environment: String
        let registeredAt: Date
    }
    private let directory: URL
    private var records: [String: Record] = [:]

    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("app-attest-keys.json")
        if let data = try? Data(contentsOf: file) { records = (try? JSONDecoder().decode([String: Record].self, from: data)) ?? [:] }
    }

    func record(for keyID: String) -> Record? { records[keyID] }

    func register(_ record: Record) throws {
        if let existing = records[record.keyID], existing.publicKey != record.publicKey { throw DiagnosticServerError.invalidAttestation }
        records[record.keyID] = record
        try persist()
    }

    func advanceCounter(keyID: String, to counter: Int) throws {
        guard var record = records[keyID], counter > record.counter else { throw DiagnosticServerError.replay }
        record.counter = counter
        records[keyID] = record
        try persist()
    }

    private func persist() throws {
        let data = try JSONEncoder.canonical.encode(records)
        try data.write(to: directory.appendingPathComponent("app-attest-keys.json"), options: [.atomic, .completeFileProtection])
    }
}

actor DiagnosticSessionStore {
    private let directory: URL
    private let retention: TimeInterval
    private let maximumRecords: Int
    init(directory: URL, retention: TimeInterval = 7 * 86_400, maximumRecords: Int = 500) throws {
        self.directory = directory; self.retention = retention; self.maximumRecords = maximumRecords
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func put(_ session: PhysicalDiagnosticSession, now: Date = .now) throws -> Bool {
        try validate(session)
        try cleanup(now: now)
        let file = directory.appendingPathComponent("\(session.sessionID.uuidString.lowercased()).json")
        let data = try JSONEncoder.canonical.encode(session)
        if let existing = try? Data(contentsOf: file) {
            guard existing == data else { throw DiagnosticServerError.duplicateConflict }
            return false
        }
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        try cleanup(now: now)
        return true
    }

    func records() throws -> [PhysicalDiagnosticSession] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(PhysicalDiagnosticSession.self, from: Data(contentsOf: $0)) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private func validate(_ value: PhysicalDiagnosticSession) throws {
        guard value.schema == PhysicalDiagnosticSession.schemaVersion,
              value.feature == "voice", value.liveTestID == "MS-800-LIVE-VOICE-QA",
              value.events.count <= 250, value.build > 0, value.endedAt >= value.startedAt,
              value.events.enumerated().allSatisfy({ $0.offset + 1 == $0.element.sequence }) else {
            throw DiagnosticServerError.invalidSchema
        }
        let forbidden = ["transcript", "audio", "password", "token", "secret", "contact", "message", "photo", "document", "location"]
        let allowedMarkers = DiagnosticSchema.allowedVoiceMarkers
        for event in value.events {
            guard allowedMarkers.contains(event.marker), event.attributes.count <= 16,
                  event.attributes.allSatisfy({ $0.key.count <= 64 && $0.value.count <= 256 }) else { throw DiagnosticServerError.invalidSchema }
            if event.attributes.contains(where: { key, _ in forbidden.contains(where: { key.lowercased().contains($0) }) }) {
                throw DiagnosticServerError.forbiddenField
            }
        }
    }

    private func cleanup(now: Date) throws {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.pathExtension == "json" }
            .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        for (index, file) in files.enumerated() {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if index >= maximumRecords || now.timeIntervalSince(modified) > retention { try? FileManager.default.removeItem(at: file) }
        }
    }
}

actor AppAttestBootstrapFailureStore {
    static let topLevelKeys: Set<String> = ["schema", "reportID", "appVersion", "build", "environment", "osVersion",
        "deviceClass", "startedAt", "endedAt", "failureStage", "errorDomain", "errorCode", "events"]

    static func validateRawSchema(_ data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], Set(root.keys) == topLevelKeys,
              let events = root["events"] as? [[String: Any]],
              events.allSatisfy({ Set($0.keys) == ["sequence", "marker", "attributes"] }),
              events.allSatisfy({ event in
                  guard let attributes = event["attributes"] as? [String: Any] else { return false }
                  return attributes.values.allSatisfy { $0 is String }
              }) else { throw DiagnosticServerError.invalidSchema }
    }

    static func decodeTransport(_ data: Data) throws -> AppAttestBootstrapFailureReport {
        try validateRawSchema(data)
        return try JSONDecoder().decode(AppAttestBootstrapFailureReport.self, from: data)
    }

    private let directory: URL
    private let retention: TimeInterval
    private let maximumRecords: Int
    init(directory: URL, retention: TimeInterval = 7 * 86_400, maximumRecords: Int = 100) throws {
        self.directory = directory; self.retention = retention; self.maximumRecords = maximumRecords
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func put(_ report: AppAttestBootstrapFailureReport, now: Date = .now) throws -> Bool {
        try validate(report)
        try cleanup(now: now)
        let file = directory.appendingPathComponent("\(report.reportID.uuidString.lowercased()).json")
        let data = try JSONEncoder.canonical.encode(report)
        if let existing = try? Data(contentsOf: file) {
            guard existing == data else { throw DiagnosticServerError.duplicateConflict }
            return false
        }
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        try cleanup(now: now)
        return true
    }

    private func validate(_ report: AppAttestBootstrapFailureReport) throws {
        let allowedMarkers: Set<String> = ["environment", "is_supported", "generate_key_invoked", "generate_key_succeeded",
            "key_id_loaded", "key_id_persisted", "challenge_received", "attest_key_invoked", "attest_key_succeeded",
            "registration_request_constructed", "registration_request_attempted", "registration_succeeded", "http_result", "bootstrap_failed"]
        let allowedAttributes: Set<String> = ["value", "correlation", "stage", "error_domain", "error_code", "http_status"]
        guard report.schema == 1, report.build >= 12, report.environment == "internal-testflight",
              report.endedAt >= report.startedAt, report.failureStage.count <= 64,
              report.errorDomain.count <= 128, report.events.count <= 30,
              report.appVersion.count <= 32, report.osVersion.count <= 32, report.deviceClass.count <= 32,
              report.errorDomain.allSatisfy({ $0.isLetter || $0.isNumber || ".-_".contains($0) }),
              report.events.enumerated().allSatisfy({ $0.offset + 1 == $0.element.sequence }),
              report.events.last?.marker == "bootstrap_failed" else { throw DiagnosticServerError.invalidSchema }
        for event in report.events {
            guard allowedMarkers.contains(event.marker), event.attributes.count <= 5,
                  event.attributes.allSatisfy({ allowedAttributes.contains($0.key) && $0.value.count <= 128 }) else {
                throw DiagnosticServerError.invalidSchema
            }
        }
        let encoded = String(data: try JSONEncoder.canonical.encode(report), encoding: .utf8)?.lowercased() ?? ""
        for forbidden in ["transcript", "audio", "password", "token", "secret", "contact", "message", "photo", "document", "location", "attestation", "keyid"] {
            if encoded.contains("\"\(forbidden)") { throw DiagnosticServerError.forbiddenField }
        }
    }

    private func cleanup(now: Date) throws {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.pathExtension == "json" }
            .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        for (index, file) in files.enumerated() {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if index >= maximumRecords || now.timeIntervalSince(modified) > retention { try? FileManager.default.removeItem(at: file) }
        }
    }
}

enum DiagnosticSchema {
    static let allowedVoiceMarkers: Set<String> = [
        "start_listening_invoked", "state_transition", "state_delivered_to_view_model", "speech_permission_before",
        "speech_permission_after", "microphone_permission_before", "microphone_permission", "recognizer_ready",
        "recognition_request_created", "audio_session_activated", "audio_tap_installed", "audio_engine_started",
        "recognition_task_created", "audio_buffer_received", "buffer_appended", "recognition_callback", "voice_start_failed",
        "route_change", "route_change_ignored", "stop_invoked", "recognition_task_cancelled", "recognition_task_finished",
        "end_audio_called", "partial_transcript", "final_transcript", "transcript_delivered_to_ui",
        "transcript_delivered_to_view_model", "transcript_delivered_to_router", "router_received", "router_accepted",
        "router_rejected", "execution_started", "visible_result", "audio_interruption"
    ]
}

struct ProductionAppAttestVerifier: @unchecked Sendable {
    let appID = AppAttest.AppID(teamID: "9V5XXDXF3N", bundleID: "com.universalassistant.app")

    func verifyAttestation(challenge: Data, keyID: Data, attestation: Data) throws -> AppAttest.AttestationResult {
        let developmentAAGUID = Data("appattestdevelop".utf8)
        let productionAAGUID = Data("appattest".utf8) + Data(repeating: 0, count: 7)
        guard attestation.range(of: productionAAGUID) != nil, attestation.range(of: developmentAAGUID) == nil else {
            throw DiagnosticServerError.invalidAttestation
        }
        return try AppAttest.verifyAttestation(
            challenge: challenge,
            request: .init(attestation: attestation, keyID: keyID),
            appID: appID
        )
    }

    func verifyAssertion(challenge: Data, clientData: Data, assertion: Data, publicKey: Data) throws -> Int {
        let key = try P256.Signing.PublicKey(x963Representation: publicKey)
        _ = try AppAttest.verifyAssertion(
            challenge: challenge,
            request: .init(assertion: assertion, clientData: clientData, challenge: challenge),
            previousResult: nil,
            publicKey: key,
            appID: appID
        )
        let rpHash = Data(SHA256.hash(data: Data("9V5XXDXF3N.com.universalassistant.app".utf8)))
        let ranges = assertion.ranges(of: rpHash)
        guard ranges.count == 1 else { throw DiagnosticServerError.invalidAssertion }
        let start = ranges[0].upperBound
        guard assertion.count >= start + 5 else { throw DiagnosticServerError.invalidAssertion }
        return assertion[(start + 1)..<(start + 5)].reduce(0) { ($0 << 8) | Int($1) }
    }
}

extension Application {
    func configurePhysicalDiagnostics(storageRoot: URL) throws {
        let challenges = ChallengeStore()
        let registrations = try AppAttestRegistrationStore(directory: storageRoot.appendingPathComponent("attestation"))
        let diagnostics = try DiagnosticSessionStore(directory: storageRoot.appendingPathComponent("sessions"))
        let bootstrapFailures = try AppAttestBootstrapFailureStore(directory: storageRoot.appendingPathComponent("bootstrap"))
        let verifier = ProductionAppAttestVerifier()
        let challengeRateLimit = PrincipalRateLimiter(policy: .init(maximumRequests: 20, window: 60))
        let ingestRateLimit = PrincipalRateLimiter(policy: .init(maximumRequests: 60, window: 60))
        let bootstrapRateLimit = PrincipalRateLimiter(policy: .init(maximumRequests: 5, window: 60))
        routes.defaultMaxBodySize = "96kb"

        get("health") { _ in HealthResponse() }
        post("v1", "app-attest", "challenge") { request async throws -> ChallengeResponse in
            guard await challengeRateLimit.allow(subjectID: request.remoteAddress?.description ?? "unknown") else { throw Abort(.tooManyRequests) }
            let body = try request.content.decode(ChallengeRequest.self)
            let issued: (UUID, ChallengeStore.Entry)
            do { issued = try await challenges.issue(operation: body.operation) }
            catch { throw Abort(.badRequest) }
            return .init(challengeID: issued.0, challenge: issued.1.value.base64EncodedString(), expiresAt: issued.1.expiresAt)
        }
        post("v1", "app-attest", "register") { request async throws -> AttestationRegistrationResponse in
            guard await challengeRateLimit.allow(subjectID: request.remoteAddress?.description ?? "unknown") else { throw Abort(.tooManyRequests) }
            let body = try request.content.decode(AttestationRegistrationRequest.self)
            let challenge: ChallengeStore.Entry
            do { challenge = try await challenges.consume(id: body.challengeID, operation: "attest") }
            catch { throw Abort(.unauthorized) }
            guard let keyID = Data(base64Encoded: body.keyID), let attestation = Data(base64Encoded: body.attestation) else { throw Abort(.badRequest) }
            let result: AppAttest.AttestationResult
            do { result = try verifier.verifyAttestation(challenge: challenge.value, keyID: keyID, attestation: attestation) }
            catch { throw Abort(.unauthorized) }
            try await registrations.register(.init(keyID: body.keyID, publicKey: result.publicKey.x963Representation, counter: 0, environment: "production", registeredAt: .now))
            return .init(status: "registered")
        }
        post("v1", "app-attest", "bootstrap-failure") { request async throws -> BootstrapReceiptResponse in
            guard await bootstrapRateLimit.allow(subjectID: request.remoteAddress?.description ?? "unknown") else { throw Abort(.tooManyRequests) }
            if let rawLength = request.headers.first(name: "content-length"), let length = Int(rawLength), length > 8_192 {
                throw Abort(.payloadTooLarge)
            }
            guard let buffer = request.body.data else { throw Abort(.badRequest) }
            let raw = Data(buffer.readableBytesView)
            let report: AppAttestBootstrapFailureReport
            do { report = try AppAttestBootstrapFailureStore.decodeTransport(raw) }
            catch { throw Abort(.badRequest) }
            do { _ = try await bootstrapFailures.put(report) }
            catch DiagnosticServerError.invalidSchema { throw Abort(.badRequest) }
            catch DiagnosticServerError.forbiddenField { throw Abort(.badRequest) }
            return .init(reportID: report.reportID, status: "stored-unverified-bootstrap", receivedAt: .now)
        }
        post("v1", "diagnostics") { request async throws -> ReceiptResponse in
            guard await ingestRateLimit.allow(subjectID: request.remoteAddress?.description ?? "unknown") else { throw Abort(.tooManyRequests) }
            let body = try request.content.decode(AssertionEnvelope.self)
            guard let assertion = Data(base64Encoded: body.assertion), let clientData = Data(base64Encoded: body.clientData),
                  clientData.count <= 80_000, let registration = await registrations.record(for: body.keyID) else { throw Abort(.unauthorized) }
            let decoded: DiagnosticAssertionClientData
            do { decoded = try JSONDecoder().decode(DiagnosticAssertionClientData.self, from: clientData) }
            catch { throw Abort(.badRequest) }
            let challenge: ChallengeStore.Entry
            do { challenge = try await challenges.consume(id: decoded.challengeID, operation: "diagnostic") }
            catch { throw Abort(.unauthorized) }
            guard decoded.challenge == challenge.value.base64EncodedString(), decoded.operation == "diagnostic" else { throw Abort(.unauthorized) }
            let counter: Int
            do { counter = try verifier.verifyAssertion(challenge: challenge.value, clientData: clientData, assertion: assertion, publicKey: registration.publicKey) }
            catch { throw Abort(.unauthorized) }
            do { try await registrations.advanceCounter(keyID: body.keyID, to: counter) }
            catch { throw Abort(.unauthorized) }
            do { _ = try await diagnostics.put(decoded.diagnostic) }
            catch DiagnosticServerError.invalidSchema { throw Abort(.badRequest) }
            catch DiagnosticServerError.forbiddenField { throw Abort(.badRequest) }
            return .init(sessionID: decoded.diagnostic.sessionID, status: "delivered", receivedAt: .now)
        }
    }
}

extension JSONEncoder {
    static var canonical: JSONEncoder {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension Data {
    func ranges(of needle: Data) -> [Range<Int>] {
        guard !needle.isEmpty, count >= needle.count else { return [] }
        return (0...(count - needle.count)).compactMap { index in
            self[index..<(index + needle.count)].elementsEqual(needle) ? index..<(index + needle.count) : nil
        }
    }
}
