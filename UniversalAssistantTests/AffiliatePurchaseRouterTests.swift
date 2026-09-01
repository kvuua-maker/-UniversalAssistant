import Foundation
import Testing
@testable import UniversalAssistant

private func handoffOffer(url: String = "https://shop.example/product/exact-sku?variant=black") -> NormalizedOffer {
    let zero = CostComponent(value: Money(amount: 0, currency: "UAH"), knowledge: .known)
    let identity = ProductIdentity(brand: "Brand", model: "Model", productType: "phone", sku: "SKU", gtin: nil,
                                   variant: .init(color: "black", condition: .new))
    return .init(id: "offer", providerID: "shop", providerOfferID: "exact-sku", identity: identity,
                 identityMatch: .init(level: .exact, evidence: ["sku"], conflicts: []),
                 seller: .init(id: "seller", name: "Seller"), availability: .inStock,
                 cost: .init(item: .init(amount: 1, currency: "UAH"), shipping: zero, tax: zero, duties: zero, requiredOther: zero),
                 exactPurchaseURL: URL(string: url)!, sourceTimestamp: .now, fetchedAt: .now,
                 affiliateAttributionSupported: true)
}

private let routingConfig = AffiliateRoutingConfiguration(
    providerID: "shop", allowedHosts: ["shop.example"], allowedParameterNames: ["aff_id", "sub_id"],
    parameterValues: ["aff_id": "campaign", "sub_id": "click"], officiallyVerifiedAt: .now
)

@Suite("Affiliate purchase routing") struct AffiliatePurchaseRouterTests {
    @Test func appliesOnlyAllowlistedAttributionAndPreservesVariant() throws {
        let result = try AffiliatePurchaseRouter().route(handoffOffer(), configuration: routingConfig)
        let items = URLComponents(url: result.destination, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains(.init(name: "variant", value: "black")))
        #expect(items.contains(.init(name: "aff_id", value: "campaign")))
        #expect(result.attribution == .outboundParametersApplied)
        #expect(result.state == .destinationPrepared)
    }

    @Test func missingConfigurationFallsBackToExactOfferNotHomepage() throws {
        let offer = handoffOffer()
        let result = try AffiliatePurchaseRouter().route(offer, configuration: nil)
        #expect(result.destination == offer.exactPurchaseURL)
        #expect(result.attribution == .notConfigured)
    }

    @Test func homepageAndWrongProviderAreRejected() {
        #expect(throws: AffiliateRoutingError.invalidExactDestination) {
            try AffiliatePurchaseRouter().route(handoffOffer(url: "https://shop.example/"), configuration: nil)
        }
        let wrong = AffiliateRoutingConfiguration(providerID: "other", allowedHosts: ["shop.example"],
                                                   allowedParameterNames: [], parameterValues: [:], officiallyVerifiedAt: .now)
        #expect(throws: AffiliateRoutingError.providerMismatch) {
            try AffiliatePurchaseRouter().route(handoffOffer(), configuration: wrong)
        }
    }

    @Test func unknownTrackingParameterIsRejected() {
        let unsafe = AffiliateRoutingConfiguration(providerID: "shop", allowedHosts: ["shop.example"],
                                                    allowedParameterNames: ["aff_id"], parameterValues: ["invented": "x"],
                                                    officiallyVerifiedAt: .now)
        #expect(throws: AffiliateRoutingError.parameterNotAllowed) {
            try AffiliatePurchaseRouter().route(handoffOffer(), configuration: unsafe)
        }
    }

    @Test func verifiedExactAppHandoffCarriesAttributionParameters() throws {
        var offer = handoffOffer()
        offer.exactAppURL = URL(string: "shopapp://product/exact-sku?variant=black")!
        var configuration = routingConfig
        configuration.allowedAppSchemes = ["shopapp"]
        let result = try AffiliatePurchaseRouter().route(offer, configuration: configuration)
        let items = URLComponents(url: result.destination, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(result.destination.scheme == "shopapp")
        #expect(items.contains(.init(name: "aff_id", value: "campaign")))
        #expect(items.contains(.init(name: "variant", value: "black")))
    }
}
