import Foundation
import Testing
@testable import UniversalAssistant

private func offer(id: String, seller: String, price: Decimal = 1000, exact: Bool = true,
                   affiliate: Bool = false, shippingKnown: Bool = true,
                   providerID: String = "provider") -> NormalizedOffer {
    let money = Money(amount: price, currency: "UAH")
    let component = CostComponent(value: shippingKnown ? Money(amount: 100, currency: "UAH") : nil,
                                  knowledge: shippingKnown ? .known : .unknown)
    let zero = CostComponent(value: Money(amount: 0, currency: "UAH"), knowledge: .known)
    let identity = ProductIdentity(brand: "Brand", model: "Model", productType: "phone", sku: "SKU", gtin: nil,
                                   variant: .init(color: "black", condition: .new))
    return .init(id: id, providerID: providerID, providerOfferID: id, identity: identity,
                 identityMatch: .init(level: exact ? .exact : .approximate, evidence: [], conflicts: []),
                 seller: .init(id: seller, name: seller, rating: 4.8, reviewCount: 10, isOfficialStore: true,
                               buyerProtection: "protected", returns: "14 days", warranty: "1 year"),
                 availability: .inStock, cost: .init(item: money, shipping: component, tax: zero, duties: zero, requiredOther: zero),
                 deliversToUkraine: true, exactPurchaseURL: URL(string: "https://example.com/offer/\(id)")!,
                 sourceTimestamp: .now, fetchedAt: .now, affiliateAttributionSupported: affiliate)
}

@Suite("Normalized commerce offers") struct NormalizedOfferTests {
    @Test func unknownCostNeverBecomesInventedTotal() {
        #expect(offer(id: "a", seller: "s", shippingKnown: false).cost.calculableTotal == nil)
        #expect(offer(id: "b", seller: "s").cost.calculableTotal?.amount == 1100)
    }

    @Test func mixedCurrenciesNeverBecomeInventedTotal() {
        let base = offer(id: "a", seller: "s").cost
        let usd = CostComponent(value: Money(amount: 2, currency: "USD"), knowledge: .known)
        let mixed = OfferTotalCost(item: base.item, shipping: usd, tax: base.tax, duties: base.duties, requiredOther: base.requiredOther)
        #expect(mixed.calculableTotal == nil)
    }

    @Test func rankingIsIndependentOfAffiliateCommissionSignal() {
        let plain = offer(id: "plain", seller: "a", affiliate: false)
        let affiliate = offer(id: "affiliate", seller: "b", affiliate: true)
        #expect(OfferRanker().rank([plain, affiliate]).map(\.id) == ["plain", "affiliate"])
    }

    @Test func exactVariantOutranksCheaperApproximation() {
        let exact = offer(id: "exact", seller: "a", price: 1500)
        let approximate = offer(id: "approx", seller: "b", price: 500, exact: false)
        #expect(OfferRanker().rank([approximate, exact]).first?.id == "exact")
    }

    @Test func dedupDoesNotMergeDifferentSellers() {
        let first = offer(id: "same", seller: "a")
        let duplicate = first
        let otherSeller = offer(id: "same", seller: "b")
        #expect(OfferDeduplicator().deduplicate([first, duplicate, otherSeller]).count == 2)
    }

    @Test func partnerResultReplacesGenericDuplicateButDistinctVariantRemains() {
        let generic = offer(id: "web", seller: "shop", providerID: "generic-retail-web")
        let partner = offer(id: "api", seller: "shop", providerID: "partner-api")
        let otherVariantBase = offer(id: "other", seller: "shop", providerID: "generic-retail-web")
        let otherVariant = NormalizedOffer(
            id: otherVariantBase.id, providerID: otherVariantBase.providerID,
            providerOfferID: otherVariantBase.providerOfferID,
            identity: .init(brand: "Brand", model: "Model", productType: "phone", sku: "SKU",
                            gtin: nil, variant: .init(color: "blue", condition: .new)),
            identityMatch: otherVariantBase.identityMatch, seller: otherVariantBase.seller,
            availability: otherVariantBase.availability, cost: otherVariantBase.cost,
            deliversToUkraine: otherVariantBase.deliversToUkraine,
            deliveryETA: otherVariantBase.deliveryETA, exactPurchaseURL: otherVariantBase.exactPurchaseURL,
            sourceTimestamp: otherVariantBase.sourceTimestamp, fetchedAt: otherVariantBase.fetchedAt,
            affiliateAttributionSupported: false)
        let result = OfferDeduplicator().deduplicate([generic, partner, otherVariant])
        #expect(result.map(\.providerID) == ["partner-api", "generic-retail-web"])
    }

    @Test func verifiedPersonalEffectivePriceCanImproveUserRankingWithoutCommissionSignal() {
        var personal = offer(id: "personal", seller: "a", price: 1_200)
        personal.personalPrice = .init(publicPrice: .init(amount: 1_200, currency: "UAH"),
            effectivePrice: .init(amount: 800, currency: "UAH"), appliedBenefitIDs: ["loyalty"],
            deliveryEffect: nil, sourceReference: "merchant:quote", verifiedAt: .now,
            confidence: .verifiedPartner)
        let publicOnly = offer(id: "public", seller: "b", price: 900)
        #expect(OfferRanker().rank([publicOnly, personal]).first?.id == "personal")
    }
}
