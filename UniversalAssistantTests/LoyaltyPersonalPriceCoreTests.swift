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

    private func component(_ id: String, _ kind: LoyaltyPriceComponentKind, _ amount: Decimal,
                           funding: LoyaltyBenefitFunding = .customer, semantic: String? = nil) -> LoyaltyPriceComponent {
        .init(id: id, kind: kind, funding: funding, amount: .init(amount: amount, currency: "UAH"),
              sourceReference: "contract:\(id)", verifiedAt: now, semanticBenefitID: semantic ?? id)
    }

    private func integrityPolicy(state: LoyaltyCommercialRuleState = .verified,
                                 combinations: Set<String> = [], crossDevice: Bool = true,
                                 installments: LoyaltyCommercialRuleState = .compatible,
                                 basis: LoyaltyCommissionBasis? = .netAfterDiscounts,
                                 rate: Decimal? = 0.10,
                                 reversal: LoyaltyCommercialRuleState = .verified) -> LoyaltyStackingPolicy {
        .init(id: "policy-v1", merchantID: "shop", version: 1, effectiveFrom: now.addingTimeInterval(-60),
              state: state, allowedCombinations: combinations, attributionMethods: [.affiliateLink],
              crossDeviceSupported: crossDevice, installmentCompatibility: installments,
              commissionBasis: basis, commissionRate: rate, fixedCommission: nil, refundReversal: reversal,
              evidenceReference: "partner-contract:v1")
    }

    private func checkout(components: [LoyaltyPriceComponent] = [], policy: LoyaltyStackingPolicy? = nil,
                          user: String = "u1", loyaltyUser: String? = "u1", crossDevice: Bool = false,
                          installments: Bool = false, available: Bool? = true,
                          attribution: CommissionEligibility = .eligible) -> LoyaltyCheckoutContext {
        .init(userID: user, loyaltyAccountUserID: loyaltyUser, merchantID: "shop", orderID: "order-1",
              publicPrice: .init(amount: 1_000, currency: "UAH"), components: components, policy: policy,
              attribution: .init(eligibility: attribution, method: attribution == .eligible ? .affiliateLink : nil,
                                 strategyID: "program-v1", reason: "test"),
              referralCreatedAt: now.addingTimeInterval(-30), isCrossDevice: crossDevice,
              usesInstallments: installments, variantIsAvailable: available, quotedAt: now)
    }

    @Test func compatibleLoyaltyAndCommissionPreserveBoth() throws {
        let combo = "customerLoyalty+partnerDiscount"
        let result = try LoyaltyCommissionIntegrityEngine().evaluate(checkout(
            components: [component("loyalty", .customerLoyalty, 100), component("partner", .partnerDiscount, 50, funding: .partner)],
            policy: integrityPolicy(combinations: [combo])), now: now)
        #expect(result.payablePrice?.amount == 850)
        #expect(result.attributionState == .established)
        #expect(result.commissionAmount?.amount == 85)
        #expect(result.commissionState == .pendingPartnerConfirmation)
    }

    @Test func incompatibleBenefitsChooseVerifiedBestUserValueWithoutHidingIt() throws {
        let result = try LoyaltyCommissionIntegrityEngine().evaluate(checkout(
            components: [component("loyalty", .customerLoyalty, 200), component("coupon", .coupon, 50)],
            policy: integrityPolicy()), now: now)
        #expect(result.payablePrice?.amount == 800)
        #expect(result.appliedComponentIDs == ["loyalty"])
        #expect(result.reason == "best_user_value_verified_subset")
    }

    @Test func couponLoyaltyCompatibleAndIncompatibleAreProviderConfigured() throws {
        let components = [component("loyalty", .customerLoyalty, 100), component("coupon", .coupon, 80)]
        let key = "coupon+customerLoyalty"
        #expect(try LoyaltyCommissionIntegrityEngine().evaluate(checkout(components: components, policy: integrityPolicy(combinations: [key])), now: now).payablePrice?.amount == 820)
        #expect(try LoyaltyCommissionIntegrityEngine().evaluate(checkout(components: components, policy: integrityPolicy()), now: now).payablePrice?.amount == 900)
    }

    @Test func sameBenefitCannotBeDoubleApplied() {
        #expect(throws: LoyaltyIntegrityError.duplicateBenefit) {
            try LoyaltyCommissionIntegrityEngine().evaluate(checkout(
                components: [component("a", .coupon, 100, semantic: "same"), component("b", .partnerDiscount, 100, semantic: "same")],
                policy: integrityPolicy(combinations: ["coupon+partnerDiscount"])), now: now)
        }
    }

    @Test func unknownStackingPolicyNeverGuessesCompatibilityOrCommission() throws {
        let result = try LoyaltyCommissionIntegrityEngine().evaluate(checkout(
            components: [component("loyalty", .customerLoyalty, 100)], policy: integrityPolicy(state: .unknown)), now: now)
        #expect(result.payablePrice?.amount == 1_000)
        #expect(result.commissionState == .unknown)
    }

    @Test func loginScopeCannotLeakLoyaltyAcrossUsers() {
        #expect(throws: LoyaltyIntegrityError.userScopeMismatch) {
            try LoyaltyCommissionIntegrityEngine().evaluate(checkout(policy: integrityPolicy(), user: "u1", loyaltyUser: "u2"), now: now)
        }
    }

    @Test func accountDisconnectInvalidatesCachedPersonalPrice() async throws {
        let cache = LoyaltyAccountQuoteCache()
        let value = try LoyaltyCommissionIntegrityEngine().evaluate(checkout(policy: integrityPolicy()), now: now)
        await cache.put(.init(userID: "u1", merchantID: "shop", value: value, expiresAt: now.addingTimeInterval(60)))
        #expect(await cache.value(userID: "u1", merchantID: "shop", now: now) != nil)
        await cache.disconnect(userID: "u1", merchantID: "shop")
        #expect(await cache.value(userID: "u1", merchantID: "shop", now: now) == nil)
    }

    @Test func attributedDeepLinkIsRequiredButExternalHandoffIsNotCompletion() throws {
        let result = try LoyaltyCommissionIntegrityEngine().evaluate(checkout(policy: integrityPolicy()), now: now)
        #expect(result.attributedHandoffRequired)
        #expect(result.completion == .handoffOnly)
    }

    @Test func crossDeviceAttributionRequiresExplicitPartnerSupport() throws {
        #expect(try LoyaltyCommissionIntegrityEngine().evaluate(checkout(policy: integrityPolicy(crossDevice: false), crossDevice: true), now: now).attributionState == .unknown)
        #expect(try LoyaltyCommissionIntegrityEngine().evaluate(checkout(policy: integrityPolicy(crossDevice: true), crossDevice: true), now: now).attributionState == .established)
    }

    @Test func installmentCompatibilityIsNeverAssumed() throws {
        #expect(try LoyaltyCommissionIntegrityEngine().evaluate(checkout(policy: integrityPolicy(installments: .unknown), installments: true), now: now).attributionState == .unknown)
    }

    @Test func priceOrVariantChangeInvalidatesStaleEconomics() throws {
        let result = try LoyaltyCommissionIntegrityEngine().evaluate(checkout(
            components: [component("coupon", .coupon, 100)], policy: integrityPolicy(), available: false), now: now)
        #expect(result.payablePrice == nil)
        #expect(result.reason == "variant_unavailable")
    }

    @Test func netCommissionUsesActualDiscountedAmountNotCatalogPrice() throws {
        let result = try LoyaltyCommissionIntegrityEngine().evaluate(checkout(
            components: [component("personal", .personalPrice, 250)], policy: integrityPolicy()), now: now)
        #expect(result.payablePrice?.amount == 750)
        #expect(result.commissionAmount?.amount == 75)
    }

    @Test func unknownCommissionBasisNeverProducesApproximateRevenue() throws {
        let result = try LoyaltyCommissionIntegrityEngine().evaluate(checkout(policy: integrityPolicy(basis: nil, rate: nil)), now: now)
        #expect(result.commissionAmount == nil)
        #expect(result.commissionState == .unknown)
    }

    @Test func fullAndPartialRefundWaitForPartnerConfirmationThenAdjustExactly() {
        let engine = LoyaltyCommissionIntegrityEngine()
        let policy = integrityPolicy()
        let pending = engine.adjustedCommission(original: .init(amount: 80, currency: "UAH"), refunded: .init(amount: 400, currency: "UAH"), orderNet: .init(amount: 800, currency: "UAH"), partnerConfirmed: false, policy: policy)
        #expect(pending.0.amount == 80 && pending.1 == .pendingPartnerConfirmation)
        let partial = engine.adjustedCommission(original: .init(amount: 80, currency: "UAH"), refunded: .init(amount: 200, currency: "UAH"), orderNet: .init(amount: 800, currency: "UAH"), partnerConfirmed: true, policy: policy)
        #expect(partial.0.amount == 60 && partial.1 == .partiallyReversed)
        let full = engine.adjustedCommission(original: .init(amount: 80, currency: "UAH"), refunded: .init(amount: 800, currency: "UAH"), orderNet: .init(amount: 800, currency: "UAH"), partnerConfirmed: true, policy: policy)
        #expect(full.0.amount == 0 && full.1 == .reversed)
    }

    @Test func uaFundedBenefitRemainsSeparatelyTypedFromCustomerAndPartnerBenefits() {
        let values = [component("customer", .customerLoyalty, 10), component("partner", .partnerDiscount, 20, funding: .partner), component("ua", .uaFundedBenefit, 30, funding: .universalAssistant)]
        #expect(values.map(\.funding) == [.customer, .partner, .universalAssistant])
    }

}
