import Foundation
import Testing
@testable import UniversalAssistant

private func separationOffer(_ id: String, price: Decimal, affiliate: Bool) -> NormalizedOffer {
    let zero = CostComponent(value: .init(amount: 0, currency: "USD"), knowledge: .known)
    return .init(id: id, providerID: id, providerOfferID: id,
        identity: .init(brand: "Brand", model: id, productType: "item", sku: id, gtin: nil,
                        variant: .init(color: nil, condition: .new)),
        identityMatch: .init(level: .exact, evidence: [], conflicts: []),
        seller: .init(id: id, name: id, rating: 5, reviewCount: 10, isOfficialStore: true,
                      buyerProtection: nil, returns: nil, warranty: nil),
        availability: .inStock, cost: .init(item: .init(amount: price, currency: "USD"),
                                            shipping: zero, tax: zero, duties: zero, requiredOther: zero),
        deliversToUkraine: true, exactPurchaseURL: URL(string: "https://example.test/\(id)")!,
        sourceTimestamp: .now, fetchedAt: .now, affiliateAttributionSupported: affiliate)
}

@Suite("Sponsored and organic result separation")
struct SponsoredResultSeparationTests {
    @Test func sponsoredPlacementIsSeparateAndExplicitlyDisclosed() throws {
        let now = Date(), better = separationOffer("better-nonpartner", price: 10, affiliate: false)
        let sponsored = separationOffer("sponsored", price: 100, affiliate: true)
        let campaign = SponsoredCampaign(campaignID: "campaign", offerID: sponsored.id,
            startsAt: now.addingTimeInterval(-1), endsAt: now.addingTimeInterval(100),
            budget: .init(amount: 100, currency: "USD"), spent: .init(amount: 1, currency: "USD"),
            disclosureByLanguageCode: ["uk": "Реклама"], enabled: true)
        let result = try SponsoredResultSeparator().separate(offers: [sponsored, better], campaigns: [campaign],
                                                              languageCode: "uk", now: now)
        #expect(result.organic.first?.id == "better-nonpartner")
        #expect(result.organic.map(\.id).contains("better-nonpartner"))
        #expect(result.sponsored == [.init(offer: sponsored, campaignID: "campaign", disclosure: "Реклама")])
    }

    @Test func missingLocaleDisclosureCannotMasqueradeAsSponsoredResult() throws {
        let now = Date(), offer = separationOffer("offer", price: 10, affiliate: true)
        let campaign = SponsoredCampaign(campaignID: "campaign", offerID: offer.id,
            startsAt: now.addingTimeInterval(-1), endsAt: now.addingTimeInterval(100),
            budget: .init(amount: 10, currency: "USD"), spent: .init(amount: 0, currency: "USD"),
            disclosureByLanguageCode: ["en": "Sponsored"], enabled: true)
        let result = try SponsoredResultSeparator().separate(offers: [offer], campaigns: [campaign],
                                                              languageCode: "uk", now: now)
        #expect(result.sponsored.isEmpty)
        #expect(result.organic == [offer])
    }
}
