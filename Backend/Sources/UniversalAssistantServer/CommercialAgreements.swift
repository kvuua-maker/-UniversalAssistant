import Foundation

enum CommercialModel: String, CaseIterable, Codable, Sendable {
    case percentOfConfirmedSale = "PERCENT_OF_CONFIRMED_SALE"
    case fixedPerConfirmedOrder = "FIXED_PER_CONFIRMED_ORDER"
    case fixedPerConfirmedBooking = "FIXED_PER_CONFIRMED_BOOKING"
    case fixedPerConfirmedGuest = "FIXED_PER_CONFIRMED_GUEST"
    case fixedPerQualifiedLead = "FIXED_PER_QUALIFIED_LEAD"
    case fixedPerCompletedService = "FIXED_PER_COMPLETED_SERVICE"
    case newCustomerBounty = "NEW_CUSTOMER_BOUNTY"
    case affiliateNetworkCommission = "AFFILIATE_NETWORK_COMMISSION"
    case businessSubscription = "BUSINESS_SUBSCRIPTION"
    case sponsoredPlacement = "SPONSORED_PLACEMENT"
    case customContract = "CUSTOM_CONTRACT"
}

enum CommercialAgreementStatus: String, Codable, Sendable { case draft, active, expired, suspended, terminated }

struct CommercialTerms: Equatable, Codable, Sendable {
    let model: CommercialModel
    let rateOrValue: Decimal
    let currencyCode: String
    let qualifyingEvent: String
    let attributionWindowSeconds: Int
    let refundPolicyReference: String
    let settlementPolicyReference: String
    let geographyCodes: [String]
    let scopeReferences: [String]
    let floor: Decimal?
    let cap: Decimal?
}

struct CommercialAgreementVersion: Equatable, Codable, Sendable {
    let agreementID: UUID
    let partnerID: UUID
    let version: Int
    let effectiveFrom: Date
    let effectiveUntil: Date?
    let terms: CommercialTerms
    let status: CommercialAgreementStatus
    let recordedAt: Date
}

enum CommercialAgreementError: Error, Equatable, Sendable {
    case invalidTerms
    case duplicateVersion
    case overlappingEffectivePeriod
    case noApplicableAgreement
}

actor CommercialAgreementRegistry {
    private var versions: [UUID: [CommercialAgreementVersion]] = [:]

    func append(_ agreement: CommercialAgreementVersion) throws {
        guard Self.valid(agreement) else { throw CommercialAgreementError.invalidTerms }
        let existing = versions[agreement.agreementID, default: []]
        guard !existing.contains(where: { $0.version == agreement.version }) else {
            throw CommercialAgreementError.duplicateVersion
        }
        guard !existing.contains(where: { Self.overlaps($0, agreement) }) else {
            throw CommercialAgreementError.overlappingEffectivePeriod
        }
        versions[agreement.agreementID, default: []].append(agreement)
        versions[agreement.agreementID]?.sort { $0.version < $1.version }
    }

    func applicable(agreementID: UUID, qualifyingEventAt: Date) throws -> CommercialAgreementVersion {
        guard let agreement = versions[agreementID]?.first(where: {
            $0.status == .active && $0.effectiveFrom <= qualifyingEventAt &&
            ($0.effectiveUntil.map { qualifyingEventAt < $0 } ?? true)
        }) else { throw CommercialAgreementError.noApplicableAgreement }
        return agreement
    }

    func history(agreementID: UUID) -> [CommercialAgreementVersion] {
        versions[agreementID, default: []]
    }

    private static func valid(_ agreement: CommercialAgreementVersion) -> Bool {
        let terms = agreement.terms
        let currency = terms.currencyCode.uppercased()
        return agreement.version > 0 && agreement.effectiveUntil.map { $0 > agreement.effectiveFrom } ?? true &&
            terms.rateOrValue >= 0 && terms.attributionWindowSeconds >= 0 &&
            currency.count == 3 && !terms.qualifyingEvent.isEmpty &&
            !terms.refundPolicyReference.isEmpty && !terms.settlementPolicyReference.isEmpty &&
            (terms.floor.map { $0 >= 0 } ?? true) && (terms.cap.map { $0 >= 0 } ?? true) &&
            !(terms.floor != nil && terms.cap != nil && terms.floor! > terms.cap!)
    }

    private static func overlaps(_ lhs: CommercialAgreementVersion, _ rhs: CommercialAgreementVersion) -> Bool {
        guard lhs.partnerID == rhs.partnerID else { return false }
        let lhsEnd = lhs.effectiveUntil ?? .distantFuture
        let rhsEnd = rhs.effectiveUntil ?? .distantFuture
        return lhs.effectiveFrom < rhsEnd && rhs.effectiveFrom < lhsEnd
    }
}
