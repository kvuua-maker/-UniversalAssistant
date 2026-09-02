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
