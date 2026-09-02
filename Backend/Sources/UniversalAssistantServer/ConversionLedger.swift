import Foundation

struct AttributionRecord: Equatable, Codable, Sendable {
    let attributionID: UUID
    let partnerID: UUID
    let source: String
    let pseudonymousReference: String?
    let offerReference: String
    let campaignReference: String?
    let agreementID: UUID
    let agreementVersion: Int
    let createdAt: Date
    let expiresAt: Date
}

enum ConversionState: String, Codable, Sendable {
    case initiated = "INITIATED", pending = "PENDING", confirmed = "CONFIRMED"
    case rejected = "REJECTED", cancelled = "CANCELLED", refunded = "REFUNDED"
    case partiallyRefunded = "PARTIALLY_REFUNDED", payable = "PAYABLE", paid = "PAID"
    case disputed = "DISPUTED"
}

struct LedgerMoney: Equatable, Codable, Sendable {
    let amount: Decimal
    let currencyCode: String
}

enum CommissionEntryKind: String, Codable, Sendable { case accrual, refundAdjustment, disputeAdjustment }

struct CommissionLedgerEntry: Equatable, Codable, Sendable {
    let sequence: Int
    let conversionID: UUID
    let partnerID: UUID
    let agreementID: UUID
    let agreementVersion: Int
    let externalTransactionID: String
    let grossAmount: LedgerMoney
    let commissionBasis: LedgerMoney
    let configuredRateOrValue: Decimal
    let commissionAmount: LedgerMoney
    let kind: CommissionEntryKind
    let sourceEvidenceReference: String
    let eventID: String
    let recordedAt: Date
}

struct ConversionAuditEvent: Equatable, Codable, Sendable {
    let sequence: Int
    let eventID: String
    let from: ConversionState
    let to: ConversionState
    let reasonCode: String
    let evidenceReference: String
    let actorReference: String
    let occurredAt: Date
}

struct ConversionRecord: Equatable, Codable, Sendable {
    let conversionID: UUID
    let attribution: AttributionRecord
    let externalTransactionID: String
    let grossAmount: LedgerMoney
    var state: ConversionState
    var refundedGrossAmount: Decimal
    var auditTrail: [ConversionAuditEvent]
    var ledger: [CommissionLedgerEntry]
}

enum ConversionLedgerError: Error, Equatable, Sendable {
    case invalidAttribution, invalidMoney, invalidEvent, invalidTransition
    case attributionExpired, agreementMismatch, refundExceedsGross
}

actor ConversionLedger {
    private var conversions: [UUID: ConversionRecord] = [:]
    private var processedEventIDs: Set<String> = []

    func initiate(
        attribution: AttributionRecord, externalTransactionID: String,
        grossAmount: LedgerMoney, eventID: String, evidence: String,
        actor: String, at: Date = .now
    ) throws -> ConversionRecord {
        guard Self.valid(attribution), attribution.expiresAt >= at else { throw ConversionLedgerError.attributionExpired }
        guard Self.valid(grossAmount), grossAmount.amount >= 0 else { throw ConversionLedgerError.invalidMoney }
        guard Self.nonempty(externalTransactionID), Self.validEvent(eventID, evidence, actor) else { throw ConversionLedgerError.invalidEvent }
        if processedEventIDs.contains(eventID), let existing = conversions.values.first(where: { $0.auditTrail.first?.eventID == eventID }) {
            return existing
        }
        let id = UUID()
        let audit = ConversionAuditEvent(sequence: 1, eventID: eventID, from: .initiated, to: .initiated,
                                         reasonCode: "conversion_initiated", evidenceReference: evidence,
                                         actorReference: actor, occurredAt: at)
        let record = ConversionRecord(conversionID: id, attribution: attribution,
                                      externalTransactionID: externalTransactionID, grossAmount: grossAmount,
                                      state: .initiated, refundedGrossAmount: 0, auditTrail: [audit], ledger: [])
        conversions[id] = record; processedEventIDs.insert(eventID)
        return record
    }

    func transition(
        _ conversionID: UUID, to next: ConversionState, agreement: CommercialAgreementVersion,
        eventID: String, reason: String, evidence: String, actor: String,
        refundGrossAmount: Decimal? = nil, at: Date = .now
    ) throws -> ConversionRecord {
        guard var record = conversions[conversionID], Self.validEvent(eventID, evidence, actor), Self.nonempty(reason)
        else { throw ConversionLedgerError.invalidEvent }
        if processedEventIDs.contains(eventID) { return record }
        guard record.attribution.agreementID == agreement.agreementID,
              record.attribution.agreementVersion == agreement.version,
              record.attribution.partnerID == agreement.partnerID else { throw ConversionLedgerError.agreementMismatch }
        guard Self.allowed(record.state, next) else { throw ConversionLedgerError.invalidTransition }

        if next == .confirmed {
            let amount = try Self.commission(gross: record.grossAmount, terms: agreement.terms)
            record.ledger.append(Self.entry(record, agreement, amount: amount, kind: .accrual,
                                            eventID: eventID, evidence: evidence, at: at))
        }
        if next == .refunded || next == .partiallyRefunded {
            let remainingGross = record.grossAmount.amount - record.refundedGrossAmount
            let refund = refundGrossAmount ?? (next == .refunded ? remainingGross : -1)
            guard refund > 0, record.refundedGrossAmount + refund <= record.grossAmount.amount else {
                throw ConversionLedgerError.refundExceedsGross
            }
            let adjustment = try Self.refundCommission(record: record, refund: refund, agreement: agreement)
            record.refundedGrossAmount += refund
            record.ledger.append(Self.entry(record, agreement, amount: adjustment, kind: .refundAdjustment,
                                            eventID: eventID, evidence: evidence, at: at))
        }
        record.auditTrail.append(.init(sequence: record.auditTrail.count + 1, eventID: eventID,
                                       from: record.state, to: next, reasonCode: reason,
                                       evidenceReference: evidence, actorReference: actor, occurredAt: at))
        record.state = next
        conversions[conversionID] = record; processedEventIDs.insert(eventID)
        return record
    }

    func record(_ id: UUID) -> ConversionRecord? { conversions[id] }

    private static func commission(gross: LedgerMoney, terms: CommercialTerms) throws -> LedgerMoney {
        guard gross.currencyCode.uppercased() == terms.currencyCode.uppercased() else { throw ConversionLedgerError.invalidMoney }
        let amount: Decimal
        switch terms.model {
        case .percentOfConfirmedSale: amount = gross.amount * terms.rateOrValue / 100
        default: amount = terms.rateOrValue
        }
        return .init(amount: min(max(amount, terms.floor ?? amount), terms.cap ?? amount), currencyCode: gross.currencyCode.uppercased())
    }

    private static func refundCommission(record: ConversionRecord, refund: Decimal, agreement: CommercialAgreementVersion) throws -> LedgerMoney {
        let original = try commission(gross: record.grossAmount, terms: agreement.terms).amount
        let proportional = record.grossAmount.amount == 0 ? 0 : original * refund / record.grossAmount.amount
        return .init(amount: -proportional, currencyCode: record.grossAmount.currencyCode.uppercased())
    }

    private static func entry(_ record: ConversionRecord, _ agreement: CommercialAgreementVersion,
                              amount: LedgerMoney, kind: CommissionEntryKind, eventID: String,
                              evidence: String, at: Date) -> CommissionLedgerEntry {
        .init(sequence: record.ledger.count + 1, conversionID: record.conversionID,
              partnerID: agreement.partnerID, agreementID: agreement.agreementID,
              agreementVersion: agreement.version, externalTransactionID: record.externalTransactionID,
              grossAmount: record.grossAmount, commissionBasis: record.grossAmount,
              configuredRateOrValue: agreement.terms.rateOrValue, commissionAmount: amount,
              kind: kind, sourceEvidenceReference: evidence, eventID: eventID, recordedAt: at)
    }

    private static func allowed(_ from: ConversionState, _ to: ConversionState) -> Bool {
        switch (from, to) {
        case (.initiated, .pending), (.initiated, .confirmed), (.pending, .confirmed),
             (.initiated, .rejected), (.pending, .rejected), (.pending, .cancelled),
             (.confirmed, .cancelled), (.confirmed, .refunded), (.confirmed, .partiallyRefunded),
             (.partiallyRefunded, .partiallyRefunded), (.partiallyRefunded, .refunded),
             (.confirmed, .payable), (.partiallyRefunded, .payable), (.payable, .paid),
             (.confirmed, .disputed), (.payable, .disputed), (.disputed, .payable),
             (.disputed, .cancelled), (.disputed, .refunded): return true
        default: return false
        }
    }

    private static func valid(_ attribution: AttributionRecord) -> Bool {
        attribution.createdAt < attribution.expiresAt && nonempty(attribution.source) && nonempty(attribution.offerReference)
    }
    private static func valid(_ money: LedgerMoney) -> Bool { money.currencyCode.count == 3 }
    private static func validEvent(_ id: String, _ evidence: String, _ actor: String) -> Bool {
        nonempty(id) && nonempty(evidence) && nonempty(actor)
    }
    private static func nonempty(_ value: String) -> Bool { !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
