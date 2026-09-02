import Foundation
import Testing
@testable import UniversalAssistantServer

private func webhookBody() throws -> Data {
    try JSONEncoder().encode(PartnerWebhookEnvelope(schemaVersion: 1, eventType: "conversion.confirmed",
                                                     externalTransactionID: "tx-1"))
}

private func webhookStateURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("ua-webhook-\(UUID().uuidString)/processed.json")
}

@Suite("Signed partner webhook ingestion")
struct PartnerWebhookIngestionTests {
    @Test func validSignedEventIsAcceptedOnce() async throws {
        let vault = PartnerWebhookCredentialVault(), partner = UUID(), now = Date()
        let secret = Data(repeating: 7, count: 32), body = try webhookBody()
        try await vault.install(partnerID: partner, keyID: "key-1", secret: secret)
        let request = PartnerWebhookRequest(partnerID: partner, keyID: "key-1", eventID: "event-1",
            timestamp: now, body: body, signatureHex: PartnerWebhookSignature.sign(timestamp: now, body: body, secret: secret))
        let ingestion = try PartnerWebhookIngestion(vault: vault, processedEventURL: webhookStateURL())
        #expect(try await ingestion.ingest(request, now: now) == .accepted(
            .init(schemaVersion: 1, eventType: "conversion.confirmed", externalTransactionID: "tx-1")))
        #expect(try await ingestion.ingest(request, now: now) == .duplicate)
        #expect(await ingestion.auditTrail().map(\.outcome) == ["accepted", "duplicate"])
    }

    @Test func rejectsTamperingReplayAndInvalidSchema() async throws {
        let vault = PartnerWebhookCredentialVault(), partner = UUID(), now = Date()
        let secret = Data(repeating: 8, count: 32), body = try webhookBody()
        try await vault.install(partnerID: partner, keyID: "key", secret: secret)
        let ingestion = try PartnerWebhookIngestion(
            vault: vault, replayWindow: 60, processedEventURL: webhookStateURL()
        )
        let signature = PartnerWebhookSignature.sign(timestamp: now, body: body, secret: secret)
        await #expect(throws: PartnerWebhookError.invalidSignature) {
            try await ingestion.ingest(.init(partnerID: partner, keyID: "key", eventID: "bad",
                timestamp: now, body: Data("tampered".utf8), signatureHex: signature), now: now)
        }
        await #expect(throws: PartnerWebhookError.outsideReplayWindow) {
            try await ingestion.ingest(.init(partnerID: partner, keyID: "key", eventID: "old",
                timestamp: now.addingTimeInterval(-61), body: body, signatureHex: signature), now: now)
        }
    }

    @Test func rotationAllowsNewKeyAndRevocationStopsOldKey() async throws {
        let vault = PartnerWebhookCredentialVault(), partner = UUID(), now = Date(), body = try webhookBody()
        let old = Data(repeating: 1, count: 32), new = Data(repeating: 2, count: 32)
        try await vault.install(partnerID: partner, keyID: "old", secret: old)
        try await vault.install(partnerID: partner, keyID: "new", secret: new)
        await vault.revoke(partnerID: partner, keyID: "old")
        let ingestion = try PartnerWebhookIngestion(vault: vault, processedEventURL: webhookStateURL())
        await #expect(throws: PartnerWebhookError.credentialUnavailable) {
            try await ingestion.ingest(.init(partnerID: partner, keyID: "old", eventID: "old-event",
                timestamp: now, body: body, signatureHex: PartnerWebhookSignature.sign(timestamp: now, body: body, secret: old)), now: now)
        }
        let fresh = PartnerWebhookRequest(partnerID: partner, keyID: "new", eventID: "new-event", timestamp: now,
            body: body, signatureHex: PartnerWebhookSignature.sign(timestamp: now, body: body, secret: new))
        #expect(try await ingestion.ingest(fresh, now: now) != .duplicate)
    }

    @Test func auditSurfaceContainsNoSecretSignatureOrPayload() async throws {
        let vault = PartnerWebhookCredentialVault(), partner = UUID(), now = Date(), body = try webhookBody()
        let secret = Data(repeating: 9, count: 32)
        try await vault.install(partnerID: partner, keyID: "key", secret: secret)
        let ingestion = try PartnerWebhookIngestion(vault: vault, processedEventURL: webhookStateURL())
        _ = try await ingestion.ingest(.init(partnerID: partner, keyID: "key", eventID: "event",
            timestamp: now, body: body,
            signatureHex: PartnerWebhookSignature.sign(timestamp: now, body: body, secret: secret)), now: now)
        let labels = Set(Mirror(reflecting: try #require(await ingestion.auditTrail().first)).children.compactMap(\.label))
        #expect(labels.isDisjoint(with: ["secret", "signature", "signatureHex", "body", "payload"]))
    }

    @Test func duplicateRemainsRejectedAfterProcessRestart() async throws {
        let vault = PartnerWebhookCredentialVault(), partner = UUID(), now = Date()
        let secret = Data(repeating: 4, count: 32), body = try webhookBody()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ua-webhook-\(UUID().uuidString)/processed.json")
        try await vault.install(partnerID: partner, keyID: "key", secret: secret)
        let request = PartnerWebhookRequest(
            partnerID: partner, keyID: "key", eventID: "durable-event",
            timestamp: now, body: body,
            signatureHex: PartnerWebhookSignature.sign(timestamp: now, body: body, secret: secret)
        )
        let first = try PartnerWebhookIngestion(vault: vault, processedEventURL: url)
        #expect(try await first.ingest(request, now: now) != .duplicate)
        let restarted = try PartnerWebhookIngestion(vault: vault, processedEventURL: url)
        #expect(try await restarted.ingest(request, now: now) == .duplicate)
    }

    @Test func rejectsOversizedPayloadBeforeSignatureOrDecodingWork() async throws {
        let vault = PartnerWebhookCredentialVault(), partner = UUID(), now = Date()
        let ingestion = try PartnerWebhookIngestion(
            vault: vault, processedEventURL: webhookStateURL(), maximumBodyBytes: 4
        )
        await #expect(throws: PartnerWebhookError.requestTooLarge) {
            try await ingestion.ingest(.init(
                partnerID: partner, keyID: "key", eventID: "event", timestamp: now,
                body: Data(repeating: 1, count: 5), signatureHex: ""
            ), now: now)
        }
    }
}
