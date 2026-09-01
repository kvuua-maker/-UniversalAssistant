import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Grocery basket truth") struct GroceryBasketEngineTests {
    private let parser = GroceryListParser()
    private let engine = GroceryBasketEngine()

    @Test func naturalLanguageQuantitiesNormalizeToBaseUnits() throws {
        let basket = try parser.parse("2 л молока, 500 г сиру, хліб")
        #expect(basket.items.map(\.name) == ["молока", "сиру", "хліб"])
        #expect(basket.items[0].quantity == (try GroceryQuantity(amount: 2000, unit: .milliliter)))
        #expect(basket.items[1].quantity == (try GroceryQuantity(amount: 500, unit: .gram)))
        #expect(basket.items[2].quantity == (try GroceryQuantity(amount: 1, unit: .piece)))
    }

    @Test func unitPriceUsesNormalizedPackQuantity() throws {
        let quote = GroceryQuotedItem(requestedItemID: "milk", productName: "Milk", match: .exact,
                                      suppliedQuantity: try .init(amount: 2_000, unit: .milliliter),
                                      linePrice: .init(amount: 100, currency: "UAH"))
        #expect(quote.unitPrice == Money(amount: Decimal(string: "0.05")!, currency: "UAH"))
    }

    @Test func missingAndSubstituteItemsNeverProduceCompleteClaim() throws {
        let basket = try parser.parse("молоко, хліб, сир")
        let quote = GroceryStoreQuote(storeID: "silpo", storeName: "Сільпо", sourceTimestamp: .now, items: [
            .init(requestedItemID: "item-0", productName: "Молоко", match: .exact, suppliedQuantity: basket.items[0].quantity, linePrice: .init(amount: 50, currency: "UAH")),
            .init(requestedItemID: "item-1", productName: nil, match: .unavailable, suppliedQuantity: nil, linePrice: nil),
            .init(requestedItemID: "item-2", productName: "Інший сир", match: .substitute, suppliedQuantity: basket.items[2].quantity, linePrice: .init(amount: 80, currency: "UAH"))
        ])
        let total = try engine.total(basket: basket, quote: quote)
        #expect(!total.isComplete)
        #expect(total.unavailableItemIDs == ["item-1"])
        #expect(total.substituteItemIDs == ["item-2"])
        #expect(total.subtotal == Money(amount: 130, currency: "UAH"))
    }

    @Test func completeBasketsRankBeforeCheaperIncompleteOnes() throws {
        let basket = try parser.parse("молоко")
        func quote(_ id: String, price: Decimal, match: GroceryProductMatch) -> GroceryStoreQuote {
            .init(storeID: id, storeName: id, sourceTimestamp: .now, items: [
                .init(requestedItemID: "item-0", productName: "Milk", match: match,
                      suppliedQuantity: basket.items[0].quantity, linePrice: .init(amount: price, currency: "UAH"))
            ])
        }
        let totals = try engine.compare(basket: basket, quotes: [quote("cheap", price: 10, match: .substitute), quote("exact", price: 20, match: .exact)])
        #expect(totals.map(\.storeID) == ["exact", "cheap"])
    }
}
