import Foundation
import Testing
@testable import UniversalAssistant

private func presentationOffer(
    id: String,
    total: Decimal,
    seller: String,
    official: Bool = false,
    eta: TimeInterval
) -> NormalizedOffer {
    let zero = CostComponent(value: Money(amount: 0, currency: "UAH"), knowledge: .known)
    return .init(
        id: id, providerID: "provider", providerOfferID: id,
        identity: .init(brand: "Apple", model: "iPhone", productType: "phone", sku: id, gtin: nil,
                        variant: .init(storage: "128 GB", color: "Black", condition: .new)),
        identityMatch: .init(level: .exact, evidence: ["sku"], conflicts: []),
        seller: .init(id: seller, name: seller, isOfficialStore: official), availability: .inStock,
        cost: .init(item: .init(amount: total, currency: "UAH"), shipping: zero, tax: zero, duties: zero, requiredOther: zero),
        deliversToUkraine: true, deliveryETA: .init(start: .now, duration: eta),
        exactPurchaseURL: URL(string: "https://example.com/\(id)")!, sourceTimestamp: .now,
        fetchedAt: .now, affiliateAttributionSupported: false
    )
}

@Suite("Commerce native presentation") struct CommercePresentationTests {
    @Test func objectiveBadgesRequireUniqueEvidence() {
        let cheap = presentationOffer(id: "cheap", total: 900, seller: "a", eta: 200)
        let fast = presentationOffer(id: "fast", total: 1000, seller: "b", official: true, eta: 100)
        let result = CommerceOfferPresentation.make(from: [cheap, fast])
        #expect(result[0].badges == [.bestTotalPrice])
        #expect(result[1].badges == [.fastestDelivery, .officialStore])

        let tie = CommerceOfferPresentation.make(from: [cheap, presentationOffer(id: "same", total: 900, seller: "c", eta: 300)])
        #expect(!tie[0].badges.contains(.bestTotalPrice))
        #expect(!tie[1].badges.contains(.bestTotalPrice))
    }

    @Test func exactVariantAndTruthfulDiscountArePresented() {
        var offer = presentationOffer(id: "one", total: 800, seller: "a", eta: 100)
        offer.originalItemPrice = .init(amount: 1000, currency: "UAH")
        let value = CommerceOfferPresentation.make(from: [offer])[0]
        #expect(value.title == "Apple iPhone")
        #expect(value.variant == "128 GB · Black")
        #expect(value.discountPercentage == 20)
    }

    @Test func mixedCurrenciesNeverClaimBestTotalPrice() {
        let hryvnia = presentationOffer(id: "uah", total: 1000, seller: "a", eta: 100)
        var euro = presentationOffer(id: "eur", total: 20, seller: "b", eta: 200)
        let zero = CostComponent(value: Money(amount: 0, currency: "EUR"), knowledge: .known)
        euro = .init(id: euro.id, providerID: euro.providerID, providerOfferID: euro.providerOfferID,
                     identity: euro.identity, identityMatch: euro.identityMatch, seller: euro.seller,
                     availability: euro.availability,
                     cost: .init(item: .init(amount: 20, currency: "EUR"), shipping: zero, tax: zero, duties: zero, requiredOther: zero),
                     deliversToUkraine: true, deliveryETA: euro.deliveryETA,
                     exactPurchaseURL: euro.exactPurchaseURL, sourceTimestamp: euro.sourceTimestamp,
                     fetchedAt: euro.fetchedAt, affiliateAttributionSupported: false)
        let result = CommerceOfferPresentation.make(from: [hryvnia, euro])
        #expect(result.allSatisfy { !$0.badges.contains(.bestTotalPrice) })
    }

    @MainActor @Test func progressiveUpdatesKeepVisibleOrderStable() {
        let state = CommerceResultsState()
        let first = presentationOffer(id: "first", total: 1000, seller: "a", eta: 100)
        let second = presentationOffer(id: "second", total: 900, seller: "b", eta: 200)
        state.apply(.init(response: .init(offers: [first], failures: [], isFromCache: false), isComplete: false))
        state.apply(.init(response: .init(offers: [second, first], failures: [], isFromCache: false), isComplete: true))
        #expect(state.offers.map(\.id) == ["first", "second"])
        #expect(state.isComplete)
    }
}
