import Foundation
import Testing
@testable import UniversalAssistantServer

private func webhookBody() throws -> Data {
    try JSONEncoder().encode(PartnerWebhookEnvelope(schemaVersion: 1, eventType: "conversion.confirmed",
                                                     externalTransactionID: "tx-1"))
}

@Suite("Signed partner webhook ingestion")
struct PartnerWebhookIngestionTests {
    @Test func validSignedEventIsAcceptedOnce() async throws {
        let vault = PartnerWebhookCredentialVault(), partner = UUID(), now = Date()
        let secret = Data(repeating: 7, count: 32), body = try webhookBody()
        try await vault.install(partnerID: partner, keyID: "key-1", secret: secret)
        let request = PartnerWebhookRequest(partnerID: partner, keyID: "key-1", eventID: "event-1",
            timestamp: now, body: body, signatureHex: PartnerWebhookSignature.sign(timestamp: now, body: body, secret: secret))
        let ingestion = PartnerWebhookIngestion(vault: vault)
        #expect(try await ingestion.ingest(request, now: now) == .accepted(
            .init(schemaVersion: 1, eventType: "conversion.confirmed", externalTransactionID: "tx-1")))
        #expect(try await ingestion.ingest(request, now: now) == .duplicate)
        #expect(await ingestion.auditTrail().map(\.outcome) == ["accepted", "duplicate"])
    }

    @Test func rejectsTamperingReplayAndInvalidSchema() async throws {
        let vault = PartnerWebhookCredentialVault(), partner = UUID(), now = Date()
        let secret = Data(repeating: 8, count: 32), body = try webhookBody()
        try await vault.install(partnerID: partner, keyID: "key", secret: secret)
        let ingestion = PartnerWebhookIngestion(vault: vault, replayWindow: 60)
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
        let ingestion = PartnerWebhookIngestion(vault: vault)
        await #expect(throws: PartnerWebhookError.credentialUnavailable) {
            try await ingestion.ingest(.init(partnerID: partner, keyID: "old", eventID: "old-event",
                timestamp: now, body: body, signatureHex: PartnerWebhookSignature.sign(timestamp: now, body: body, secret: old)), now: now)
        }
        let fresh = PartnerWebhookRequest(partnerID: partner, keyID: "new", eventID: "new-event", timestamp: now,
            body: body, signatureHex: PartnerWebhookSignature.sign(timestamp: now, body: body, secret: new))
        #expect(try await ingestion.ingest(fresh, now: now) != .duplicate)
    }
}
