import Foundation
import Testing
@testable import UniversalAssistantServer

private func reconciliationConversion(partner: UUID, transaction: String, state: ConversionState = .confirmed) -> ConversionRecord {
    let agreement = UUID(), id = UUID(), money = LedgerMoney(amount: 100, currencyCode: "USD")
    return .init(conversionID: id, attribution: .init(attributionID: UUID(), partnerID: partner, source: "direct",
        pseudonymousReference: nil, offerReference: "offer", campaignReference: nil, agreementID: agreement,
        agreementVersion: 1, createdAt: .distantPast, expiresAt: .distantFuture), externalTransactionID: transaction,
        grossAmount: money, state: state, refundedGrossAmount: 0, auditTrail: [], ledger: [
            .init(sequence: 1, conversionID: id, partnerID: partner, agreementID: agreement, agreementVersion: 1,
                  externalTransactionID: transaction, grossAmount: money, commissionBasis: money,
                  configuredRateOrValue: 10, commissionAmount: .init(amount: 10, currencyCode: "USD"),
                  kind: .accrual, sourceEvidenceReference: "provider", eventID: "event", recordedAt: .now)
        ])
}

@Suite("Reconciliation and settlement state")
struct ReconciliationSettlementTests {
    @Test func reconciliationDetectsMissingDuplicateAmountCurrencyStatusAndRefund() {
        let partner = UUID(), conversion = reconciliationConversion(partner: partner, transaction: "tx-1")
        let report: [PartnerSettlementLine] = [
            .init(reportLineID: "1", externalTransactionID: "tx-1", commissionAmount: .init(amount: 11, currencyCode: "USD"), conversionState: .refunded, evidenceReference: "report-1"),
            .init(reportLineID: "2", externalTransactionID: "tx-1", commissionAmount: .init(amount: 11, currencyCode: "USD"), conversionState: .refunded, evidenceReference: "report-2"),
            .init(reportLineID: "3", externalTransactionID: "external-only", commissionAmount: .init(amount: 2, currencyCode: "EUR"), conversionState: .confirmed, evidenceReference: "report-3")
        ]
        let kinds = PartnerReconciliationEngine().reconcile(partnerID: partner, internalRecords: [conversion], report: report).findings.map(\.kind)
        #expect(kinds.contains(.duplicatePartnerLine)); #expect(kinds.contains(.amountMismatch))
        #expect(kinds.contains(.unexpectedRefund)); #expect(kinds.contains(.missingFromInternalLedger))
    }

    @Test func missingPartnerLineIsReportedWithoutRewritingLedger() {
        let partner = UUID(), conversion = reconciliationConversion(partner: partner, transaction: "missing")
        let result = PartnerReconciliationEngine().reconcile(partnerID: partner, internalRecords: [conversion], report: [])
        #expect(result.findings == [.init(kind: .missingFromPartnerReport, externalTransactionID: "missing",
                                         internalValue: "10", partnerValue: nil, evidenceReference: nil)])
        #expect(conversion.ledger.count == 1)
    }

    @Test func payableIsNotPaidWithoutSeparateConfirmation() async throws {
        let conversion = reconciliationConversion(partner: UUID(), transaction: "tx")
        let registry = SettlementRegistry()
        let payable = try await registry.markPayable(conversion: conversion, settlementReference: "settlement-1",
            invoiceReference: "invoice-1", evidence: "approved-report", actor: "finance")
        #expect(payable.state == .payable)
        await #expect(throws: SettlementError.confirmationRequired) {
            try await registry.confirmPaid(conversionID: conversion.conversionID, confirmationReference: "",
                                           evidence: "bank-report", actor: "finance")
        }
        let paid = try await registry.confirmPaid(conversionID: conversion.conversionID,
            confirmationReference: "payment-confirmation-1", evidence: "bank-report", actor: "finance")
        #expect(paid.state == .paid); #expect(paid.auditTrail.map(\.state) == [.payable, .paid])
    }
}
