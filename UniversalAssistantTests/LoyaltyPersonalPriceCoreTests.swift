import Foundation
import Testing
@testable import UniversalAssistant

private actor LoyaltyMemoryStore: LoyaltyPersisting {
    var cards: [LoyaltyCard] = []
    func loadCards() -> [LoyaltyCard] { cards }
    func saveCards(_ cards: [LoyaltyCard]) { self.cards = cards }
}
private actor StrategyMemoryStore: AttributionStrategyPersisting {
    var values: [AttributionStrategy] = []
    func loadStrategies() -> [AttributionStrategy] { values }
    func saveStrategies(_ strategies: [AttributionStrategy]) { values = strategies }
}

@Suite("Loyalty, personal price and attribution preservation") struct LoyaltyPersonalPriceCoreTests {
    let now = Date(timeIntervalSince1970: 1_788_220_800)

    private func benefit(_ id: String, _ kind: LoyaltyBenefitKind, amount: Decimal? = nil,
                         knowledge: LoyaltyValueKnowledge = .verified) -> LoyaltyBenefit {
        .init(id: id, merchantID: "shop", kind: kind,
              monetaryValue: amount.map { Money(amount: $0, currency: "UAH") },
              knowledge: knowledge, sourceReference: knowledge == .verified ? "merchant-api:\(id)" : "",
              verifiedAt: knowledge == .verified ? now : nil)
    }

    private func strategy(customer: CustomerEligibility = .all,
                          loyalty: LoyaltyCompatibility = .allowed,
                          coupon: LoyaltyCompatibility = .allowed,
                          voucher: String? = nil,
                          priority: AttributionPriority = .programLastClick,
                          window: TimeInterval = 86_400) -> AttributionStrategy {
        .init(id: "program-v1", merchantID: "shop", version: 1, effectiveFrom: now.addingTimeInterval(-100),
              methods: [.affiliateLink, .subID, .serverPostback], attributionWindow: window,
              customerEligibility: customer, loyaltyCompatibility: loyalty, couponCompatibility: coupon,
              exclusiveVoucher: voucher, priority: priority, commissionExclusions: ["cancelled", "refunded"],
              adjustment: .reverseOnCancellationOrRefund, evidenceReference: "contract:v1")
    }

    private func context(returning: Bool? = false, loyalty: Bool = false, coupon: String? = nil,
                         competing: Bool = false, event: String = "confirmed",
                         referralAge: TimeInterval = 60) -> AttributionContext {
        .init(merchantID: "shop", referralCreatedAt: now.addingTimeInterval(-referralAge),
              isReturningCustomer: returning, usesLoyalty: loyalty, couponCode: coupon,
              hasCompetingAttribution: competing, event: event)
    }

    @Test func loyaltyCardDeduplicatesAndPersistsAcrossRestart() async throws {
        let persistence = LoyaltyMemoryStore()
        let first = LoyaltyCard(id: "card-1", merchantID: "shop", cardIdentifier: "12345678",
                                barcodeFormat: "code128", createdAt: now)
        let store = LoyaltyCardStore(persistence: persistence)
        try await store.save(first)
        await #expect(throws: LoyaltyCoreError.duplicateCard) {
            try await store.save(.init(id: "card-2", merchantID: "shop", cardIdentifier: "12345678", createdAt: now))
        }
        let restored = LoyaltyCardStore(persistence: persistence)
        try await restored.restore()
        #expect(await restored.snapshot() == [first])
    }

    @Test func verifiedBenefitsProduceSeparatePublicAndEffectivePrice() throws {
        let result = try PersonalPriceResolver().resolve(
            publicPrice: .init(amount: 1_000, currency: "UAH"),
            benefits: [benefit("personal", .personalPrice, amount: 100),
                       benefit("coupon", .coupon, amount: 50),
                       benefit("reward", .reward, amount: 25),
                       benefit("bonus", .bonusBalance, amount: 500)],
            deliveryEffect: .init(amount: 30, currency: "UAH"),
            sourceReference: "merchant-api:quote", verifiedAt: now, now: now)
        #expect(result.publicPrice.amount == 1_000)
        #expect(result.effectivePrice?.amount == 855)
        #expect(result.appliedBenefitIDs == ["coupon", "personal", "reward"])
    }

    @Test func unknownDiscountNeverChangesEffectivePrice() throws {
        let result = try PersonalPriceResolver().resolve(publicPrice: .init(amount: 100, currency: "UAH"),
            benefits: [benefit("unknown", .personalPrice, amount: 90, knowledge: .unknown)],
            deliveryEffect: nil, sourceReference: "merchant-api:quote", verifiedAt: now, now: now)
        #expect(result.effectivePrice == nil)
    }

    @Test func existingCustomerLoginAndLoyaltyDoNotEraseAttribution() {
        let decision = AttributionStrategyEvaluator().evaluate(
            [strategy(customer: .all, loyalty: .allowed)],
            context: context(returning: true, loyalty: true), now: now)
        #expect(decision.eligibility == .eligible)
        #expect(decision.method == .affiliateLink)
    }

    @Test func exclusiveVoucherIsAnExplicitTrackingMethod() {
        let decision = AttributionStrategyEvaluator().evaluate(
            [strategy(coupon: .disallowed, voucher: "UA-ONLY")],
            context: context(coupon: "UA-ONLY"), now: now)
        #expect(decision.method == .exclusiveVoucher)
        #expect(decision.eligibility == .eligible)
    }

    @Test func incompatibleCouponAndReturningCustomerFailTruthfully() {
        #expect(AttributionStrategyEvaluator().evaluate(
            [strategy(coupon: .disallowed)], context: context(coupon: "PUBLIC"), now: now).eligibility == .notEligible)
        #expect(AttributionStrategyEvaluator().evaluate(
            [strategy(customer: .newOnly)], context: context(returning: true), now: now).eligibility == .notEligible)
    }

    @Test func expiryAndCompetingAttributionNeverForceOrStealClick() {
        #expect(AttributionStrategyEvaluator().evaluate(
            [strategy(window: 30)], context: context(referralAge: 31), now: now).reason == "expired_or_missing_referral")
        #expect(AttributionStrategyEvaluator().evaluate(
            [strategy(priority: .preserveExisting)], context: context(competing: true), now: now).reason == "competing_attribution_preserved")
    }

    @Test func refundsAndCancellationsAreNotCommissionEligible() {
        for event in ["refunded", "cancelled"] {
            #expect(AttributionStrategyEvaluator().evaluate(
                [strategy()], context: context(event: event), now: now).eligibility == .notEligible)
        }
        #expect(strategy().adjustment == .reverseOnCancellationOrRefund)
    }

    @Test func missingMerchantContractOrLoyaltyAPIStaysUnknown() {
        #expect(AttributionStrategyEvaluator().evaluate([], context: context(), now: now).eligibility == .unknown)
        #expect(AttributionStrategyEvaluator().evaluate(
            [strategy(loyalty: .unknown)], context: context(loyalty: true), now: now).eligibility == .unknown)
    }

    @Test func versionedAttributionStrategyPersistsAcrossRestart() async throws {
        let persistence = StrategyMemoryStore()
        let registry = AttributionStrategyRegistry(persistence: persistence)
        try await registry.register(strategy())
        await #expect(throws: AttributionStrategyRegistryError.duplicateVersion) {
            try await registry.register(strategy())
        }
        let restored = AttributionStrategyRegistry(persistence: persistence)
        try await restored.restore()
        #expect(await restored.snapshot() == [strategy()])
    }
}
