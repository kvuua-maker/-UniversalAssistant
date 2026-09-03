import Foundation

enum LoyaltyConnectionKind: String, Codable, Sendable { case oauthAccount, storedCard }
enum LoyaltyBenefitKind: String, Codable, Sendable { case personalPrice, coupon, reward, bonusBalance, tier }
enum LoyaltyValueKnowledge: String, Codable, Sendable { case verified, unknown }

struct LoyaltyIdentity: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let merchantID: String
    let kind: LoyaltyConnectionKind
    let externalReference: String
    let createdAt: Date
}

struct LoyaltyCard: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let merchantID: String
    let cardIdentifier: String
    var barcodeFormat: String?
    var displayLabel: String?
    let createdAt: Date
}

struct LoyaltyBenefit: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let merchantID: String
    let kind: LoyaltyBenefitKind
    var monetaryValue: Money?
    var displayValue: String?
    let knowledge: LoyaltyValueKnowledge
    let sourceReference: String
    let verifiedAt: Date?
    var expiresAt: Date?
}

protocol MerchantLoyaltyProvider: Sendable {
    var merchantID: String { get }
    func benefits(for loyaltyIdentity: LoyaltyIdentity) async throws -> [LoyaltyBenefit]
}

protocol LoyaltyPersisting: Sendable {
    func loadCards() async throws -> [LoyaltyCard]
    func saveCards(_ cards: [LoyaltyCard]) async throws
}

actor LocalLoyaltyPersistence: LoyaltyPersisting {
    private let store: LocalStore
    init(store: LocalStore = .shared) { self.store = store }
    func loadCards() async throws -> [LoyaltyCard] { try await store.load([LoyaltyCard].self, from: "loyalty-cards.json") ?? [] }
    func saveCards(_ cards: [LoyaltyCard]) async throws { try await store.save(cards, as: "loyalty-cards.json") }
}

enum LoyaltyCoreError: Error, Equatable, Sendable { case invalidCard, duplicateCard, providerMismatch, unverifiedBenefit }

actor LoyaltyCardStore {
    private let persistence: any LoyaltyPersisting
    private var cards: [String: LoyaltyCard] = [:]
    init(persistence: any LoyaltyPersisting = LocalLoyaltyPersistence()) { self.persistence = persistence }
    func restore() async throws { cards = Dictionary(uniqueKeysWithValues: try await persistence.loadCards().map { ($0.id, $0) }) }
    func save(_ card: LoyaltyCard) async throws {
        guard !card.merchantID.trimmingCharacters(in: .whitespaces).isEmpty,
              card.cardIdentifier.filter(\.isNumber).count >= 4 else { throw LoyaltyCoreError.invalidCard }
        guard !cards.values.contains(where: { $0.merchantID == card.merchantID && $0.cardIdentifier == card.cardIdentifier && $0.id != card.id })
        else { throw LoyaltyCoreError.duplicateCard }
        cards[card.id] = card
        try await persistence.saveCards(snapshot())
    }
    func snapshot() -> [LoyaltyCard] { cards.values.sorted { $0.id < $1.id } }
}

struct VerifiedPersonalPrice: Equatable, Sendable {
    let publicPrice: Money
    let effectivePrice: Money?
    let appliedBenefitIDs: [String]
    let deliveryEffect: Money?
    let sourceReference: String
    let verifiedAt: Date
    let confidence: RetailExtractionConfidence
}

struct PersonalPriceResolver: Sendable {
    func resolve(publicPrice: Money, benefits: [LoyaltyBenefit], deliveryEffect: Money?,
                 sourceReference: String, verifiedAt: Date, now: Date = .now) throws -> VerifiedPersonalPrice {
        let eligible = benefits.filter {
            $0.knowledge == .verified && !$0.sourceReference.isEmpty &&
            $0.verifiedAt != nil && ($0.expiresAt.map { $0 >= now } ?? true)
        }
        let discounts = eligible.compactMap { benefit -> Money? in
            guard [.personalPrice, .coupon, .reward].contains(benefit.kind),
                  benefit.monetaryValue?.currency == publicPrice.currency else { return nil }
            return benefit.monetaryValue
        }
        let discount = discounts.reduce(Decimal.zero) { $0 + $1.amount }
        let delivery = deliveryEffect?.currency == publicPrice.currency ? deliveryEffect?.amount : nil
        let effective = discount > 0 || delivery != nil
            ? Money(amount: max(0, publicPrice.amount - discount + (delivery ?? 0)), currency: publicPrice.currency) : nil
        guard !sourceReference.isEmpty else { throw LoyaltyCoreError.unverifiedBenefit }
        return .init(publicPrice: publicPrice, effectivePrice: effective,
                     appliedBenefitIDs: eligible.filter {
                         [.personalPrice, .coupon, .reward].contains($0.kind) && $0.monetaryValue != nil
                     }.map(\.id).sorted(),
                     deliveryEffect: deliveryEffect?.currency == publicPrice.currency ? deliveryEffect : nil,
                     sourceReference: sourceReference, verifiedAt: verifiedAt,
                     confidence: .verifiedPartner)
    }
}

enum AttributionTrackingMethod: String, Codable, Sendable {
    case affiliateLink, clickID, subID, serverPostback, exclusiveVoucher
}
enum CustomerEligibility: String, Codable, Sendable { case all, newOnly, returningOnly }
enum LoyaltyCompatibility: String, Codable, Sendable { case allowed, disallowed, unknown }
enum AttributionPriority: String, Codable, Sendable { case preserveExisting, programLastClick, exclusiveVoucher }
enum CommissionEligibility: String, Codable, Sendable { case eligible, notEligible, unknown }
enum ConversionAdjustment: String, Codable, Sendable { case none, reverseOnCancellationOrRefund }

struct AttributionStrategy: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let merchantID: String
    let version: Int
    let effectiveFrom: Date
    var effectiveUntil: Date?
    let methods: [AttributionTrackingMethod]
    let attributionWindow: TimeInterval
    let customerEligibility: CustomerEligibility
    let loyaltyCompatibility: LoyaltyCompatibility
    let couponCompatibility: LoyaltyCompatibility
    let exclusiveVoucher: String?
    let priority: AttributionPriority
    let commissionExclusions: Set<String>
    let adjustment: ConversionAdjustment
    let evidenceReference: String
}

protocol AttributionStrategyPersisting: Sendable {
    func loadStrategies() async throws -> [AttributionStrategy]
    func saveStrategies(_ strategies: [AttributionStrategy]) async throws
}

actor LocalAttributionStrategyPersistence: AttributionStrategyPersisting {
    private let store: LocalStore
    init(store: LocalStore = .shared) { self.store = store }
    func loadStrategies() async throws -> [AttributionStrategy] {
        try await store.load([AttributionStrategy].self, from: "attribution-strategies.json") ?? []
    }
    func saveStrategies(_ strategies: [AttributionStrategy]) async throws {
        try await store.save(strategies, as: "attribution-strategies.json")
    }
}

enum AttributionStrategyRegistryError: Error, Equatable, Sendable {
    case invalidStrategy, duplicateVersion
}

actor AttributionStrategyRegistry {
    private let persistence: any AttributionStrategyPersisting
    private var strategies: [AttributionStrategy] = []
    init(persistence: any AttributionStrategyPersisting = LocalAttributionStrategyPersistence()) {
        self.persistence = persistence
    }
    func restore() async throws { strategies = try await persistence.loadStrategies() }
    func register(_ strategy: AttributionStrategy) async throws {
        guard !strategy.merchantID.isEmpty, strategy.version > 0, strategy.attributionWindow >= 0,
              !strategy.evidenceReference.isEmpty,
              strategy.effectiveUntil.map({ $0 > strategy.effectiveFrom }) ?? true
        else { throw AttributionStrategyRegistryError.invalidStrategy }
        guard !strategies.contains(where: {
            $0.merchantID == strategy.merchantID && $0.version == strategy.version
        }) else { throw AttributionStrategyRegistryError.duplicateVersion }
        strategies.append(strategy)
        strategies.sort { ($0.merchantID, $0.version) < ($1.merchantID, $1.version) }
        try await persistence.saveStrategies(strategies)
    }
    func snapshot() -> [AttributionStrategy] { strategies }
}

struct AttributionContext: Equatable, Sendable {
    let merchantID: String
    let referralCreatedAt: Date?
    let isReturningCustomer: Bool?
    let usesLoyalty: Bool
    let couponCode: String?
    let hasCompetingAttribution: Bool
    let event: String
}

struct AttributionDecision: Equatable, Sendable {
    let eligibility: CommissionEligibility
    let method: AttributionTrackingMethod?
    let strategyID: String?
    let reason: String
}

struct AttributionStrategyEvaluator: Sendable {
    func evaluate(_ strategies: [AttributionStrategy], context: AttributionContext, now: Date = .now) -> AttributionDecision {
        guard let strategy = strategies.filter({
            $0.merchantID == context.merchantID && $0.effectiveFrom <= now &&
            ($0.effectiveUntil.map { now < $0 } ?? true) && !$0.evidenceReference.isEmpty
        }).max(by: { $0.version < $1.version }) else {
            return .init(eligibility: .unknown, method: nil, strategyID: nil, reason: "no_verified_strategy")
        }
        guard let created = context.referralCreatedAt,
              now.timeIntervalSince(created) >= 0,
              now.timeIntervalSince(created) <= strategy.attributionWindow else {
            return .init(eligibility: .notEligible, method: nil, strategyID: strategy.id, reason: "expired_or_missing_referral")
        }
        if strategy.commissionExclusions.contains(context.event) {
            return .init(eligibility: .notEligible, method: nil, strategyID: strategy.id, reason: "excluded_event")
        }
        if context.usesLoyalty {
            guard strategy.loyaltyCompatibility == .allowed else {
                return .init(eligibility: strategy.loyaltyCompatibility == .unknown ? .unknown : .notEligible,
                             method: nil, strategyID: strategy.id, reason: "loyalty_rule")
            }
        }
        if context.couponCode != nil {
            guard strategy.couponCompatibility == .allowed ||
                    (strategy.exclusiveVoucher != nil && strategy.exclusiveVoucher == context.couponCode) else {
                return .init(eligibility: strategy.couponCompatibility == .unknown ? .unknown : .notEligible,
                             method: nil, strategyID: strategy.id, reason: "coupon_rule")
            }
        }
        switch (strategy.customerEligibility, context.isReturningCustomer) {
        case (.newOnly, true), (.returningOnly, false):
            return .init(eligibility: .notEligible, method: nil, strategyID: strategy.id, reason: "customer_eligibility")
        case (.newOnly, nil), (.returningOnly, nil):
            return .init(eligibility: .unknown, method: nil, strategyID: strategy.id, reason: "customer_status_unknown")
        default: break
        }
        if context.hasCompetingAttribution && strategy.priority == .preserveExisting {
            return .init(eligibility: .notEligible, method: nil, strategyID: strategy.id, reason: "competing_attribution_preserved")
        }
        let method: AttributionTrackingMethod? =
            (strategy.exclusiveVoucher != nil && strategy.exclusiveVoucher == context.couponCode ? .exclusiveVoucher : nil) ??
            strategy.methods.first
        guard let method else {
            return .init(eligibility: .unknown, method: nil, strategyID: strategy.id, reason: "no_supported_tracking_method")
        }
        return .init(eligibility: .eligible, method: method, strategyID: strategy.id, reason: "verified_contract")
    }
}


// MARK: - Loyalty / discount / attribution / commission integrity

enum LoyaltyCommercialRuleState: String, Codable, Sendable { case verified, unknown, incompatible, compatible, conditional }
enum LoyaltyPriceComponentKind: String, Codable, Sendable {
    case customerLoyalty, personalPrice, partnerDiscount, coupon, partnerCashback, uaFundedBenefit, paymentMethodDiscount, delivery
}
enum LoyaltyBenefitFunding: String, Codable, Sendable { case customer, partner, universalAssistant }
enum LoyaltyAttributionState: String, Codable, Sendable { case notEstablished, established, pendingConfirmation, confirmed, lost, expired, unknown }
enum LoyaltyCommissionState: String, Codable, Sendable { case estimatedOnly, pendingPartnerConfirmation, confirmed, reversed, partiallyReversed, unknown }
enum LoyaltyCommissionBasis: String, Codable, Sendable { case grossOrderValue, netAfterDiscounts, netAfterReturns, categorySpecific, fixedFee, otherVerified }
enum LoyaltyAccountAccessState: String, Codable, Sendable { case current, reauthRequired, disconnected, unknown }
enum LoyaltyCheckoutCompletion: String, Codable, Sendable { case handoffOnly, partnerConfirmed }

struct LoyaltyPriceComponent: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let kind: LoyaltyPriceComponentKind
    let funding: LoyaltyBenefitFunding
    let amount: Money
    let sourceReference: String
    let verifiedAt: Date
    var expiresAt: Date?
    var semanticBenefitID: String
}

struct LoyaltyStackingPolicy: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let merchantID: String
    let version: Int
    let effectiveFrom: Date
    var effectiveUntil: Date?
    let state: LoyaltyCommercialRuleState
    let allowedCombinations: Set<String>
    let attributionMethods: [AttributionTrackingMethod]
    let crossDeviceSupported: Bool
    let installmentCompatibility: LoyaltyCommercialRuleState
    let commissionBasis: LoyaltyCommissionBasis?
    let commissionRate: Decimal?
    let fixedCommission: Money?
    let refundReversal: LoyaltyCommercialRuleState
    let evidenceReference: String
}

struct LoyaltyCheckoutContext: Equatable, Sendable {
    let userID: String
    let loyaltyAccountUserID: String?
    let merchantID: String
    let orderID: String?
    let publicPrice: Money
    let components: [LoyaltyPriceComponent]
    let policy: LoyaltyStackingPolicy?
    let attribution: AttributionDecision
    let referralCreatedAt: Date?
    let isCrossDevice: Bool
    let usesInstallments: Bool
    let variantIsAvailable: Bool?
    let quotedAt: Date
}

struct LoyaltyCheckoutEconomics: Equatable, Sendable {
    let payablePrice: Money?
    let appliedComponentIDs: [String]
    let attributionState: LoyaltyAttributionState
    let commissionState: LoyaltyCommissionState
    let commissionAmount: Money?
    let completion: LoyaltyCheckoutCompletion
    let attributedHandoffRequired: Bool
    let reason: String
}

enum LoyaltyIntegrityError: Error, Equatable, Sendable { case userScopeMismatch, currencyMismatch, duplicateBenefit, invalidPolicy }

struct LoyaltyCommissionIntegrityEngine: Sendable {
    func evaluate(_ context: LoyaltyCheckoutContext, now: Date = .now) throws -> LoyaltyCheckoutEconomics {
        guard context.loyaltyAccountUserID == nil || context.loyaltyAccountUserID == context.userID else { throw LoyaltyIntegrityError.userScopeMismatch }
        guard context.variantIsAvailable != false else {
            return .init(payablePrice: nil, appliedComponentIDs: [], attributionState: .unknown, commissionState: .unknown,
                         commissionAmount: nil, completion: .handoffOnly, attributedHandoffRequired: false, reason: "variant_unavailable")
        }
        guard let policy = context.policy, !policy.evidenceReference.isEmpty, policy.effectiveFrom <= now,
              policy.effectiveUntil.map({ now < $0 }) ?? true else {
            return .init(payablePrice: context.publicPrice, appliedComponentIDs: [], attributionState: .unknown,
                         commissionState: .unknown, commissionAmount: nil, completion: .handoffOnly,
                         attributedHandoffRequired: false, reason: "commercial_policy_unknown")
        }
        guard policy.state == .verified || policy.state == .compatible || policy.state == .conditional else {
            return .init(payablePrice: context.publicPrice, appliedComponentIDs: [], attributionState: .unknown,
                         commissionState: .unknown, commissionAmount: nil, completion: .handoffOnly,
                         attributedHandoffRequired: false, reason: "stacking_not_verified")
        }
        let current = context.components.filter { component in
            component.amount.currency == context.publicPrice.currency && !component.sourceReference.isEmpty &&
            component.verifiedAt <= now && (component.expiresAt.map { now <= $0 } ?? true)
        }
        guard current.allSatisfy({ $0.amount.currency == context.publicPrice.currency }) else { throw LoyaltyIntegrityError.currencyMismatch }
        let grouped = Dictionary(grouping: current, by: \.semanticBenefitID)
        guard grouped.values.allSatisfy({ $0.count == 1 }) else { throw LoyaltyIntegrityError.duplicateBenefit }
        let kinds = Set(current.map { $0.kind.rawValue })
        let combination = kinds.sorted().joined(separator: "+")
        let compatible = current.count <= 1 || policy.allowedCombinations.contains(combination)
        let applied = compatible ? current : bestUserValueSubset(current, allowed: policy.allowedCombinations)
        let discount = applied.filter { $0.kind != .delivery && $0.kind != .partnerCashback }.reduce(Decimal.zero) { $0 + $1.amount.amount }
        let delivery = applied.filter { $0.kind == .delivery }.reduce(Decimal.zero) { $0 + $1.amount.amount }
        let payable = Money(amount: max(0, context.publicPrice.amount - discount + delivery), currency: context.publicPrice.currency)
        var attributionState: LoyaltyAttributionState
        if context.isCrossDevice && !policy.crossDeviceSupported { attributionState = .unknown }
        else if context.attribution.eligibility == .eligible { attributionState = .established }
        else if context.attribution.eligibility == .notEligible { attributionState = .lost }
        else { attributionState = .unknown }
        if context.usesInstallments && ![.verified, .compatible].contains(policy.installmentCompatibility) { attributionState = .unknown }
        let commission = commissionAmount(policy: policy, publicPrice: context.publicPrice, payable: payable)
        let commissionState: LoyaltyCommissionState = attributionState == .established && commission != nil ? .pendingPartnerConfirmation : .unknown
        return .init(payablePrice: payable, appliedComponentIDs: applied.map(\.id).sorted(), attributionState: attributionState,
                     commissionState: commissionState, commissionAmount: commission, completion: .handoffOnly,
                     attributedHandoffRequired: attributionState == .established, reason: compatible ? "verified_compatible_path" : "best_user_value_verified_subset")
    }

    func adjustedCommission(original: Money, refunded: Money, orderNet: Money,
                            partnerConfirmed: Bool, policy: LoyaltyStackingPolicy) -> (Money, LoyaltyCommissionState) {
        guard partnerConfirmed, policy.refundReversal == .verified, original.currency == refunded.currency,
              refunded.currency == orderNet.currency, orderNet.amount > 0 else { return (original, .pendingPartnerConfirmation) }
        let ratio = min(1, max(0, refunded.amount / orderNet.amount))
        let amount = max(0, original.amount * (1 - ratio))
        return (Money(amount: amount, currency: original.currency), amount == 0 ? .reversed : .partiallyReversed)
    }

    private func bestUserValueSubset(_ components: [LoyaltyPriceComponent], allowed: Set<String>) -> [LoyaltyPriceComponent] {
        var candidates = components.map { [$0] }
        if allowed.contains(components.map({ $0.kind.rawValue }).sorted().joined(separator: "+")) { candidates.append(components) }
        return candidates.min { lhs, rhs in lhs.reduce(0) { $0 + $1.amount.amount } > rhs.reduce(0) { $0 + $1.amount.amount } } ?? []
    }

    private func commissionAmount(policy: LoyaltyStackingPolicy, publicPrice: Money, payable: Money) -> Money? {
        guard let basis = policy.commissionBasis else { return nil }
        if basis == .fixedFee { return policy.fixedCommission }
        guard let rate = policy.commissionRate else { return nil }
        let base: Decimal
        switch basis {
        case .grossOrderValue: base = publicPrice.amount
        case .netAfterDiscounts, .netAfterReturns: base = payable.amount
        case .categorySpecific, .otherVerified, .fixedFee: return nil
        }
        return Money(amount: base * rate, currency: payable.currency)
    }
}

actor LoyaltyAccountQuoteCache {
    struct Entry: Equatable, Sendable { let userID: String; let merchantID: String; let value: LoyaltyCheckoutEconomics; let expiresAt: Date }
    private var entries: [String: Entry] = [:]
    func put(_ entry: Entry) { entries[entry.userID + ":" + entry.merchantID] = entry }
    func value(userID: String, merchantID: String, now: Date = .now) -> LoyaltyCheckoutEconomics? {
        guard let entry = entries[userID + ":" + merchantID], entry.expiresAt >= now else { return nil }
        return entry.value
    }
    func disconnect(userID: String, merchantID: String) { entries[userID + ":" + merchantID] = nil }
}
