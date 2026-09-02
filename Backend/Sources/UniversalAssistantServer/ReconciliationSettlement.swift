import Foundation

struct PartnerSettlementLine: Equatable, Codable, Sendable {
    let reportLineID: String
    let externalTransactionID: String
    let commissionAmount: LedgerMoney
    let conversionState: ConversionState
    let evidenceReference: String
}

enum ReconciliationMismatch: String, Codable, Sendable {
    case missingFromPartnerReport
    case missingFromInternalLedger
    case duplicatePartnerLine
    case amountMismatch
    case currencyMismatch
    case statusMismatch
    case unexpectedRefund
}

struct ReconciliationFinding: Equatable, Codable, Sendable {
    let kind: ReconciliationMismatch
    let externalTransactionID: String
    let internalValue: String?
    let partnerValue: String?
    let evidenceReference: String?
}

struct ReconciliationResult: Equatable, Codable, Sendable {
    let partnerID: UUID
    let findings: [ReconciliationFinding]
    let reconciledAt: Date
}

struct PartnerReconciliationEngine: Sendable {
    func reconcile(partnerID: UUID, internalRecords: [ConversionRecord], report: [PartnerSettlementLine], at: Date = .now) -> ReconciliationResult {
        let scopedInternal = internalRecords.filter { $0.attribution.partnerID == partnerID }
        let internalByID = Dictionary(grouping: scopedInternal, by: \.externalTransactionID)
        let reportByID = Dictionary(grouping: report, by: \.externalTransactionID)
        var findings: [ReconciliationFinding] = []

        for (transactionID, records) in internalByID.sorted(by: { $0.key < $1.key }) where reportByID[transactionID] == nil {
            findings.append(.init(kind: .missingFromPartnerReport, externalTransactionID: transactionID,
                                  internalValue: Self.netCommission(records), partnerValue: nil, evidenceReference: nil))
        }
        for (transactionID, lines) in reportByID.sorted(by: { $0.key < $1.key }) {
            guard let records = internalByID[transactionID] else {
                findings.append(.init(kind: .missingFromInternalLedger, externalTransactionID: transactionID,
                                      internalValue: nil, partnerValue: Self.money(lines[0].commissionAmount),
                                      evidenceReference: lines[0].evidenceReference)); continue
            }
            if lines.count > 1 {
                findings.append(.init(kind: .duplicatePartnerLine, externalTransactionID: transactionID,
                                      internalValue: "1", partnerValue: "\(lines.count)", evidenceReference: lines[0].evidenceReference))
            }
            let line = lines[0], record = records[0]
            let internalCurrency = record.ledger.last?.commissionAmount.currencyCode ?? record.grossAmount.currencyCode
            let internalAmount = record.ledger.reduce(Decimal.zero) { $0 + $1.commissionAmount.amount }
            if internalCurrency.uppercased() != line.commissionAmount.currencyCode.uppercased() {
                findings.append(.init(kind: .currencyMismatch, externalTransactionID: transactionID,
                                      internalValue: internalCurrency, partnerValue: line.commissionAmount.currencyCode,
                                      evidenceReference: line.evidenceReference))
            } else if internalAmount != line.commissionAmount.amount {
                findings.append(.init(kind: .amountMismatch, externalTransactionID: transactionID,
                                      internalValue: "\(internalAmount)", partnerValue: "\(line.commissionAmount.amount)",
                                      evidenceReference: line.evidenceReference))
            }
            if record.state != line.conversionState {
                let kind: ReconciliationMismatch = [.refunded, .partiallyRefunded].contains(line.conversionState) && record.refundedGrossAmount == 0
                    ? .unexpectedRefund : .statusMismatch
                findings.append(.init(kind: kind, externalTransactionID: transactionID,
                                      internalValue: record.state.rawValue, partnerValue: line.conversionState.rawValue,
                                      evidenceReference: line.evidenceReference))
            }
        }
        return .init(partnerID: partnerID, findings: findings, reconciledAt: at)
    }

    private static func netCommission(_ records: [ConversionRecord]) -> String {
        "\(records.flatMap(\.ledger).reduce(Decimal.zero) { $0 + $1.commissionAmount.amount })"
    }
    private static func money(_ value: LedgerMoney) -> String { "\(value.amount) \(value.currencyCode)" }
}

enum SettlementState: String, Codable, Sendable { case payable = "PAYABLE", paid = "PAID" }
struct SettlementAuditEvent: Equatable, Codable, Sendable {
    let sequence: Int
    let state: SettlementState
    let settlementReference: String
    let invoiceReference: String?
    let taxMetadataReference: String?
    let evidenceReference: String
    let actorReference: String
    let occurredAt: Date
}

struct SettlementRecord: Equatable, Codable, Sendable {
    let conversionID: UUID
    let partnerID: UUID
    let amount: LedgerMoney
    var state: SettlementState
    var auditTrail: [SettlementAuditEvent]
}

enum SettlementError: Error, Equatable, Sendable { case invalidReference, invalidAmount, confirmationRequired, invalidTransition }

actor SettlementRegistry {
    private var records: [UUID: SettlementRecord] = [:]

    func markPayable(conversion: ConversionRecord, settlementReference: String, invoiceReference: String? = nil,
                     taxMetadataReference: String? = nil, evidence: String, actor: String, at: Date = .now) throws -> SettlementRecord {
        guard [.confirmed, .partiallyRefunded, .payable].contains(conversion.state) else { throw SettlementError.invalidTransition }
        guard Self.present(settlementReference), Self.present(evidence), Self.present(actor) else { throw SettlementError.invalidReference }
        let currency = conversion.ledger.first?.commissionAmount.currencyCode ?? conversion.grossAmount.currencyCode
        let amount = conversion.ledger.reduce(Decimal.zero) { $0 + $1.commissionAmount.amount }
        guard amount >= 0 else { throw SettlementError.invalidAmount }
        let event = SettlementAuditEvent(sequence: 1, state: .payable, settlementReference: settlementReference,
            invoiceReference: invoiceReference, taxMetadataReference: taxMetadataReference,
            evidenceReference: evidence, actorReference: actor, occurredAt: at)
        let record = SettlementRecord(conversionID: conversion.conversionID, partnerID: conversion.attribution.partnerID,
                                      amount: .init(amount: amount, currencyCode: currency), state: .payable, auditTrail: [event])
        records[conversion.conversionID] = record; return record
    }

    func confirmPaid(conversionID: UUID, confirmationReference: String, evidence: String,
                     actor: String, at: Date = .now) throws -> SettlementRecord {
        guard var record = records[conversionID], record.state == .payable else { throw SettlementError.invalidTransition }
        guard Self.present(confirmationReference), Self.present(evidence), Self.present(actor) else { throw SettlementError.confirmationRequired }
        record.auditTrail.append(.init(sequence: record.auditTrail.count + 1, state: .paid,
            settlementReference: confirmationReference, invoiceReference: nil, taxMetadataReference: nil,
            evidenceReference: evidence, actorReference: actor, occurredAt: at))
        record.state = .paid; records[conversionID] = record; return record
    }

    func record(_ conversionID: UUID) -> SettlementRecord? { records[conversionID] }
    private static func present(_ value: String) -> Bool { !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
