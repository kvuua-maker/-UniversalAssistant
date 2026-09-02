import CryptoKit
import Foundation

struct PartnerWebhookRequest: Sendable {
    let partnerID: UUID
    let keyID: String
    let eventID: String
    let timestamp: Date
    let body: Data
    let signatureHex: String
}

struct PartnerWebhookEnvelope: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let eventType: String
    let externalTransactionID: String
}

enum PartnerWebhookOutcome: Equatable, Sendable { case accepted(PartnerWebhookEnvelope), duplicate }
enum PartnerWebhookError: Error, Equatable, Sendable {
    case credentialUnavailable, invalidSignature, outsideReplayWindow, invalidSchema, invalidEventID
}

struct PartnerWebhookAuditEvent: Equatable, Sendable {
    let partnerID: UUID
    let eventID: String
    let outcome: String
    let occurredAt: Date
}

actor PartnerWebhookCredentialVault {
    private struct Credential: Sendable { let secret: Data; var active: Bool }
    private var credentials: [UUID: [String: Credential]] = [:]

    func install(partnerID: UUID, keyID: String, secret: Data) throws {
        guard !keyID.isEmpty, secret.count >= 32 else { throw PartnerWebhookError.credentialUnavailable }
        credentials[partnerID, default: [:]][keyID] = .init(secret: secret, active: true)
    }

    func revoke(partnerID: UUID, keyID: String) {
        credentials[partnerID]?[keyID]?.active = false
    }

    func revokeAll(partnerID: UUID) {
        for keyID in credentials[partnerID, default: [:]].keys {
            credentials[partnerID]?[keyID]?.active = false
        }
    }

    func secret(partnerID: UUID, keyID: String) throws -> Data {
        guard let credential = credentials[partnerID]?[keyID], credential.active else {
            throw PartnerWebhookError.credentialUnavailable
        }
        return credential.secret
    }
}

enum PartnerWebhookSignature {
    static func sign(timestamp: Date, body: Data, secret: Data) -> String {
        let seconds = Int(timestamp.timeIntervalSince1970)
        var message = Data("\(seconds).".utf8); message.append(body)
        let code = HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: secret))
        return code.map { String(format: "%02x", $0) }.joined()
    }

    static func verify(_ supplied: String, timestamp: Date, body: Data, secret: Data) -> Bool {
        guard let suppliedData = Data(hex: supplied) else { return false }
        let expected = Data(HMAC<SHA256>.authenticationCode(
            for: Data("\(Int(timestamp.timeIntervalSince1970)).".utf8) + body,
            using: SymmetricKey(data: secret)
        ))
        return suppliedData.count == expected.count && zip(suppliedData, expected).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

actor PartnerWebhookIngestion {
    private struct ProcessedSnapshot: Codable { let keys: Set<String> }
    private let vault: PartnerWebhookCredentialVault
    private let replayWindow: TimeInterval
    private let processedEventURL: URL?
    private var processed: Set<String>
    private var audit: [PartnerWebhookAuditEvent] = []

    init(vault: PartnerWebhookCredentialVault, replayWindow: TimeInterval = 300,
         processedEventURL: URL? = nil) throws {
        self.vault = vault
        self.replayWindow = replayWindow
        self.processedEventURL = processedEventURL
        if let url = processedEventURL, FileManager.default.fileExists(atPath: url.path) {
            processed = try JSONDecoder().decode(
                ProcessedSnapshot.self, from: Data(contentsOf: url)
            ).keys
        } else {
            processed = []
        }
    }

    func ingest(_ request: PartnerWebhookRequest, now: Date = .now) async throws -> PartnerWebhookOutcome {
        guard !request.eventID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PartnerWebhookError.invalidEventID
        }
        guard abs(now.timeIntervalSince(request.timestamp)) <= replayWindow else {
            throw PartnerWebhookError.outsideReplayWindow
        }
        let secret = try await vault.secret(partnerID: request.partnerID, keyID: request.keyID)
        guard PartnerWebhookSignature.verify(request.signatureHex, timestamp: request.timestamp,
                                             body: request.body, secret: secret) else {
            throw PartnerWebhookError.invalidSignature
        }
        let deduplicationKey = "\(request.partnerID.uuidString):\(request.eventID)"
        if processed.contains(deduplicationKey) {
            audit.append(.init(partnerID: request.partnerID, eventID: request.eventID,
                               outcome: "duplicate", occurredAt: now))
            return .duplicate
        }
        guard let envelope = try? JSONDecoder().decode(PartnerWebhookEnvelope.self, from: request.body),
              envelope.schemaVersion == 1, !envelope.eventType.isEmpty,
              !envelope.externalTransactionID.isEmpty else { throw PartnerWebhookError.invalidSchema }
        processed.insert(deduplicationKey)
        try persistProcessed()
        audit.append(.init(partnerID: request.partnerID, eventID: request.eventID,
                           outcome: "accepted", occurredAt: now))
        return .accepted(envelope)
    }

    func auditTrail() -> [PartnerWebhookAuditEvent] { audit }

    private func persistProcessed() throws {
        guard let url = processedEventURL else { return }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try JSONEncoder().encode(ProcessedSnapshot(keys: processed)).write(
            to: url, options: [.atomic, .completeFileProtection]
        )
    }
}

private extension Data {
    init?(hex: String) {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var data = Data(); var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte); index = next
        }
        self = data
    }
}
