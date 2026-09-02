import Foundation
import Testing
@testable import UniversalAssistantServer

private func ledgerAgreement(id: UUID, partner: UUID, rate: Decimal = 10) -> CommercialAgreementVersion {
    .init(agreementID: id, partnerID: partner, version: 1, effectiveFrom: .distantPast, effectiveUntil: nil,
          terms: .init(model: .percentOfConfirmedSale, rateOrValue: rate, currencyCode: "USD",
                       qualifyingEvent: "confirmed", attributionWindowSeconds: 3600,
                       refundPolicyReference: "refund", settlementPolicyReference: "settlement",
                       geographyCodes: ["US"], scopeReferences: ["all"], floor: nil, cap: nil),
          status: .active, recordedAt: .distantPast)
}

@Suite("Attribution conversion commission ledger")
struct ConversionLedgerTests {
    @Test func confirmationAndPartialRefundAreExactAppendOnlyAdjustments() async throws {
        let partner = UUID(), agreementID = UUID(), now = Date(), ledger = ConversionLedger()
        let attribution = AttributionRecord(attributionID: UUID(), partnerID: partner, source: "direct",
            pseudonymousReference: "pseudo", offerReference: "offer", campaignReference: nil,
            agreementID: agreementID, agreementVersion: 1, createdAt: now.addingTimeInterval(-10), expiresAt: now.addingTimeInterval(100))
        let agreement = ledgerAgreement(id: agreementID, partner: partner)
        let initiated = try await ledger.initiate(attribution: attribution, externalTransactionID: "tx-1",
            grossAmount: .init(amount: Decimal(string: "10.01")!, currencyCode: "USD"),
            eventID: "evt-1", evidence: "provider-1", actor: "webhook", at: now)
        let confirmed = try await ledger.transition(initiated.conversionID, to: .confirmed, agreement: agreement,
            eventID: "evt-2", reason: "confirmed", evidence: "provider-2", actor: "webhook", at: now)
        #expect(confirmed.ledger.first?.commissionAmount.amount == Decimal(string: "1.001")!)
        let refunded = try await ledger.transition(initiated.conversionID, to: .partiallyRefunded, agreement: agreement,
            eventID: "evt-3", reason: "partial_refund", evidence: "provider-3", actor: "webhook",
            refundGrossAmount: Decimal(string: "2.01")!, at: now)
        #expect(refunded.ledger.map(\.commissionAmount.amount) == [Decimal(string: "1.001")!, Decimal(string: "-0.201")!])
        #expect(refunded.auditTrail.count == 3)
        let fullyRefunded = try await ledger.transition(initiated.conversionID, to: .refunded, agreement: agreement,
            eventID: "evt-4", reason: "remaining_refund", evidence: "provider-4", actor: "webhook", at: now)
        #expect(fullyRefunded.refundedGrossAmount == Decimal(string: "10.01")!)
        #expect(fullyRefunded.ledger.last?.commissionAmount.amount == Decimal(string: "-0.8")!)
    }

    @Test func duplicateEventIsIdempotentAndCreatesNoSecondCommission() async throws {
        let partner = UUID(), agreementID = UUID(), now = Date(), ledger = ConversionLedger()
        let attribution = AttributionRecord(attributionID: UUID(), partnerID: partner, source: "network",
            pseudonymousReference: nil, offerReference: "offer", campaignReference: "campaign",
            agreementID: agreementID, agreementVersion: 1, createdAt: now.addingTimeInterval(-1), expiresAt: now.addingTimeInterval(100))
        let agreement = ledgerAgreement(id: agreementID, partner: partner)
        let record = try await ledger.initiate(attribution: attribution, externalTransactionID: "tx",
            grossAmount: .init(amount: 100, currencyCode: "USD"), eventID: "create", evidence: "e1", actor: "api", at: now)
        _ = try await ledger.transition(record.conversionID, to: .confirmed, agreement: agreement,
            eventID: "confirm", reason: "confirmed", evidence: "e2", actor: "api", at: now)
        let duplicate = try await ledger.transition(record.conversionID, to: .confirmed, agreement: agreement,
            eventID: "confirm", reason: "confirmed", evidence: "e2", actor: "api", at: now)
        #expect(duplicate.ledger.count == 1)
        #expect(duplicate.auditTrail.count == 2)
    }

    @Test func disputePreservesHistoryAndRefundCannotExceedGross() async throws {
        let partner = UUID(), agreementID = UUID(), now = Date(), ledger = ConversionLedger()
        let attribution = AttributionRecord(attributionID: UUID(), partnerID: partner, source: "direct",
            pseudonymousReference: nil, offerReference: "offer", campaignReference: nil,
            agreementID: agreementID, agreementVersion: 1, createdAt: now.addingTimeInterval(-1), expiresAt: now.addingTimeInterval(100))
        let agreement = ledgerAgreement(id: agreementID, partner: partner)
        let record = try await ledger.initiate(attribution: attribution, externalTransactionID: "tx",
            grossAmount: .init(amount: 50, currencyCode: "USD"), eventID: "e1", evidence: "proof", actor: "api", at: now)
        _ = try await ledger.transition(record.conversionID, to: .confirmed, agreement: agreement,
            eventID: "e2", reason: "confirmed", evidence: "proof", actor: "api", at: now)
        let disputed = try await ledger.transition(record.conversionID, to: .disputed, agreement: agreement,
            eventID: "e3", reason: "partner_dispute", evidence: "case-1", actor: "admin", at: now)
        #expect(disputed.state == .disputed)
        #expect(disputed.auditTrail.map(\.eventID) == ["e1", "e2", "e3"])
        await #expect(throws: ConversionLedgerError.refundExceedsGross) {
            try await ledger.transition(record.conversionID, to: .refunded, agreement: agreement,
                eventID: "e4", reason: "invalid_refund", evidence: "case-1", actor: "admin",
                refundGrossAmount: 51, at: now)
        }
    }
}
