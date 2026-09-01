import Foundation

enum GroceryUnit: String, Codable, Sendable { case gram, milliliter, piece }

struct GroceryQuantity: Equatable, Codable, Sendable {
    let amount: Decimal
    let unit: GroceryUnit

    init(amount: Decimal, unit: GroceryUnit) throws {
        guard amount > 0 else { throw GroceryBasketError.invalidQuantity }
        self.amount = amount; self.unit = unit
    }

    static func normalized(amount: Decimal, token: String) throws -> Self {
        switch token.lowercased() {
        case "kg", "кг": return try .init(amount: amount * 1_000, unit: .gram)
        case "g", "г": return try .init(amount: amount, unit: .gram)
        case "l", "л": return try .init(amount: amount * 1_000, unit: .milliliter)
        case "ml", "мл": return try .init(amount: amount, unit: .milliliter)
        case "pc", "pcs", "шт": return try .init(amount: amount, unit: .piece)
        default: throw GroceryBasketError.unsupportedUnit
        }
    }
}

struct GroceryBasketItem: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let quantity: GroceryQuantity
}

struct GroceryBasket: Equatable, Sendable { let items: [GroceryBasketItem] }

enum GroceryProductMatch: Int, Comparable, Codable, Sendable {
    case unverified, unavailable, substitute, equivalentQuantity, exact
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct GroceryQuotedItem: Equatable, Sendable {
    let requestedItemID: String
    let productName: String?
    let match: GroceryProductMatch
    let suppliedQuantity: GroceryQuantity?
    let linePrice: Money?

    var unitPrice: Money? {
        guard let linePrice, let suppliedQuantity else { return nil }
        return .init(amount: linePrice.amount / suppliedQuantity.amount, currency: linePrice.currency)
    }
}

struct GroceryStoreQuote: Equatable, Sendable {
    let storeID: String
    let storeName: String
    let sourceTimestamp: Date
    let items: [GroceryQuotedItem]
}

struct GroceryBasketTotal: Equatable, Sendable {
    let storeID: String
    let storeName: String
    let subtotal: Money?
    let isComplete: Bool
    let unavailableItemIDs: [String]
    let unverifiedItemIDs: [String]
    let substituteItemIDs: [String]
}

enum GroceryBasketError: Error, Equatable, Sendable {
    case emptyBasket, invalidQuantity, unsupportedUnit, invalidItem, duplicateQuote, mixedCurrencies
}

struct GroceryListParser: Sendable {
    func parse(_ input: String) throws -> GroceryBasket {
        let segments = input.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let items: [GroceryBasketItem] = try segments.enumerated().map { index, segment in
            guard !segment.isEmpty else { throw GroceryBasketError.invalidItem }
            let pattern = #"^([0-9]+(?:[.,][0-9]+)?)\s*(кг|kg|г|g|л|l|мл|ml|шт|pcs?|)\s+(.+)$"#
            if let match = segment.wholeMatch(of: try Regex(pattern)),
               let amount = Decimal(string: String(match.output[1].substring!).replacingOccurrences(of: ",", with: ".")) {
                let unitToken = String(match.output[2].substring!)
                let name = String(match.output[3].substring!).trimmingCharacters(in: .whitespaces)
                let quantity = try GroceryQuantity.normalized(amount: amount, token: unitToken.isEmpty ? "шт" : unitToken)
                return GroceryBasketItem(id: "item-\(index)", name: name, quantity: quantity)
            }
            return GroceryBasketItem(id: "item-\(index)", name: segment, quantity: try .init(amount: 1, unit: .piece))
        }
        guard !items.isEmpty else { throw GroceryBasketError.emptyBasket }
        return .init(items: items)
    }
}

struct GroceryBasketEngine: Sendable {
    func total(basket: GroceryBasket, quote: GroceryStoreQuote) throws -> GroceryBasketTotal {
        let grouped = Dictionary(grouping: quote.items, by: \.requestedItemID)
        guard grouped.values.allSatisfy({ $0.count == 1 }) else { throw GroceryBasketError.duplicateQuote }
        let quoteByID = grouped.compactMapValues(\.first)
        var unavailable: [String] = [], unverified: [String] = [], substitutes: [String] = []
        var prices: [Money] = []

        for item in basket.items {
            guard let quoted = quoteByID[item.id] else { unverified.append(item.id); continue }
            switch quoted.match {
            case .unavailable: unavailable.append(item.id)
            case .unverified: unverified.append(item.id)
            case .substitute: substitutes.append(item.id); if let price = quoted.linePrice { prices.append(price) }
            case .equivalentQuantity, .exact:
                if let price = quoted.linePrice { prices.append(price) } else { unverified.append(item.id) }
            }
        }
        let currencies = Set(prices.map(\.currency))
        if currencies.count > 1 { throw GroceryBasketError.mixedCurrencies }
        let subtotal = currencies.first.map { currency in Money(amount: prices.reduce(0) { $0 + $1.amount }, currency: currency) }
        let complete = unavailable.isEmpty && unverified.isEmpty && substitutes.isEmpty && prices.count == basket.items.count
        return .init(storeID: quote.storeID, storeName: quote.storeName, subtotal: subtotal, isComplete: complete,
                     unavailableItemIDs: unavailable, unverifiedItemIDs: unverified, substituteItemIDs: substitutes)
    }

    func compare(basket: GroceryBasket, quotes: [GroceryStoreQuote]) throws -> [GroceryBasketTotal] {
        try quotes.map { try total(basket: basket, quote: $0) }.enumerated().sorted {
            if $0.element.isComplete != $1.element.isComplete { return $0.element.isComplete }
            guard let left = $0.element.subtotal, let right = $1.element.subtotal,
                  left.currency == right.currency else { return $0.offset < $1.offset }
            return left.amount == right.amount ? $0.offset < $1.offset : left.amount < right.amount
        }.map(\.element)
    }
}
