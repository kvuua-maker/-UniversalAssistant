import Foundation
import Testing
@testable import UniversalAssistant

private struct FoodProviderFake: FoodDeliveryProvider {
    let providerID: String
    let result: Result<[FoodDeliveryOffer], Error>
    func search(_ request: FoodDeliveryRequest) async throws -> [FoodDeliveryOffer] { try result.get() }
}
private enum FoodFakeError: Error { case failed }
private struct SlowFoodProvider: FoodDeliveryProvider {
    let providerID = "slow"
    func search(_ request: FoodDeliveryRequest) async throws -> [FoodDeliveryOffer] {
        try await Task.sleep(for: .seconds(5)); return []
    }
}

private func foodOffer(_ id: String, provider: String, totalFees: Bool = true,
                       minutes: Int? = 25, verifiedETA: Bool = true, item: Decimal = 200) -> FoodDeliveryOffer {
    .init(id: id, providerID: provider, restaurant: "Restaurant", item: .init(amount: item, currency: "UAH"),
          deliveryFee: totalFees ? .init(amount: 30, currency: "UAH") : nil,
          serviceFee: totalFees ? .init(amount: 10, currency: "UAH") : nil,
          otherRequiredFees: totalFees ? .init(amount: 0, currency: "UAH") : nil,
          deliveryMinutes: minutes, availabilityVerified: true, priceVerified: true,
          etaVerified: verifiedETA, sourceTimestamp: .now,
          orderURL: URL(string: "https://food.example/order/\(id)")!)
}

@Suite("Food delivery comparison") struct FoodDeliveryComparisonEngineTests {
    @Test func ranksByVerifiedDeliveredTotalNotMenuPrice() async {
        let cheapMenuHighFees = FoodDeliveryOffer(id: "a", providerID: "glovo", restaurant: "A",
            item: .init(amount: 100, currency: "UAH"), deliveryFee: .init(amount: 150, currency: "UAH"),
            serviceFee: .init(amount: 20, currency: "UAH"), otherRequiredFees: .init(amount: 0, currency: "UAH"),
            deliveryMinutes: 20, availabilityVerified: true, priceVerified: true, etaVerified: true,
            sourceTimestamp: .now, orderURL: URL(string: "https://glovoapp.com/order/a")!)
        let result = await FoodDeliveryComparisonEngine(providers: [
            FoodProviderFake(providerID: "glovo", result: .success([cheapMenuHighFees])),
            FoodProviderFake(providerID: "bolt", result: .success([foodOffer("b", provider: "bolt", item: 200)]))
        ]).compare(.init(query: "pizza", latitude: 50, longitude: 30, maximumDeliveryMinutes: nil))
        #expect(result.comparable.map(\.id) == ["b", "a"])
    }

    @Test func hardMaximumETARejectsUnknownAndLateOffers() async {
        let values = [foodOffer("fast", provider: "p", minutes: 25),
                      foodOffer("late", provider: "p", minutes: 50),
                      foodOffer("unknown", provider: "p", minutes: nil, verifiedETA: false)]
        let result = await FoodDeliveryComparisonEngine(providers: [FoodProviderFake(providerID: "p", result: .success(values))])
            .compare(.init(query: "pizza", latitude: 50, longitude: 30, maximumDeliveryMinutes: 30))
        #expect(result.comparable.map(\.id) == ["fast"])
    }

    @Test func incompleteFeesAreDisclosedAndProviderFailureDoesNotBreakResult() async {
        let result = await FoodDeliveryComparisonEngine(providers: [
            FoodProviderFake(providerID: "ok", result: .success([foodOffer("x", provider: "ok", totalFees: false)])),
            FoodProviderFake(providerID: "failed", result: .failure(FoodFakeError.failed))
        ]).compare(.init(query: "dish", latitude: 50, longitude: 30, maximumDeliveryMinutes: nil))
        #expect(result.comparable.isEmpty)
        #expect(result.incomplete.map(\.id) == ["x"])
        #expect(result.failures["failed"] == "provider_error")
    }

    @Test func orderIsNeverClaimedWithoutExplicitConfirmedProviderHandoff() {
        let offer = foodOffer("x", provider: "p")
        let engine = FoodDeliveryComparisonEngine(providers: [])
        #expect(engine.order(offer, confirmed: false) == .confirmationRequired)
        #expect(engine.order(offer, confirmed: true) == .confirmedHandoff(offer.orderURL))
    }

    @Test func slowProviderIsBoundedAndCannotBlockVerifiedAlternative() async {
        let result = await FoodDeliveryComparisonEngine(providers: [SlowFoodProvider(),
            FoodProviderFake(providerID: "fast", result: .success([foodOffer("fast", provider: "fast")]))],
            timeout: .milliseconds(30))
            .compare(.init(query: "pizza", latitude: 50, longitude: 30, maximumDeliveryMinutes: nil))
        #expect(result.comparable.map(\.id) == ["fast"])
        #expect(result.failures["slow"] == "provider_error")
    }
}
