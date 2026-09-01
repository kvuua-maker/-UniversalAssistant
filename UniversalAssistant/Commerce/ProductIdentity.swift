import Foundation

enum ProductCondition: String, Codable, CaseIterable, Sendable {
    case new, refurbished, used, openBox, unknown
}

struct ProductVariant: Equatable, Codable, Sendable {
    var storage: String?
    var size: String?
    var color: String?
    var generation: String?
    var region: String?
    var condition: ProductCondition = .unknown
    var configuration: String?
    var quantity: Decimal?
    var quantityUnit: String?
}

struct ProductIdentity: Equatable, Codable, Sendable {
    var brand: String?
    var model: String?
    var productType: String
    var sku: String?
    var gtin: String?
    var variant: ProductVariant

    func validated() throws -> Self {
        guard !normalized(productType).isEmpty else { throw ProductIdentityError.missingProductType }
        if let gtin, !GTINValidator().isValid(gtin) { throw ProductIdentityError.invalidGTIN }
        if let quantity = variant.quantity, quantity <= 0 { throw ProductIdentityError.invalidQuantity }
        return self
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ProductIdentityError: Error, Equatable, Sendable {
    case missingProductType, invalidGTIN, invalidQuantity
}

struct GTINValidator: Sendable {
    func isValid(_ raw: String) -> Bool {
        let digits = raw.filter(\.isNumber)
        guard [8, 12, 13, 14].contains(digits.count), digits.count == raw.count,
              let check = digits.last?.wholeNumberValue else { return false }
        let body = digits.dropLast().reversed().enumerated()
        let sum = body.reduce(0) { $0 + ($1.element.wholeNumberValue ?? 0) * ($1.offset.isMultiple(of: 2) ? 3 : 1) }
        return (10 - sum % 10) % 10 == check
    }
}

enum ProductMatchLevel: Int, Comparable, Codable, Sendable {
    case unrelated, approximate, compatible, exact
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct ProductIdentityMatch: Equatable, Sendable {
    let level: ProductMatchLevel
    let evidence: [String]
    let conflicts: [String]
}

struct ProductIdentityResolver: Sendable {
    func match(query: ProductIdentity, candidate: ProductIdentity) -> ProductIdentityMatch {
        let fields: [(String, String?, String?)] = [
            ("brand", query.brand, candidate.brand), ("model", query.model, candidate.model),
            ("storage", query.variant.storage, candidate.variant.storage), ("size", query.variant.size, candidate.variant.size),
            ("color", query.variant.color, candidate.variant.color), ("generation", query.variant.generation, candidate.variant.generation),
            ("region", query.variant.region, candidate.variant.region), ("configuration", query.variant.configuration, candidate.variant.configuration),
            ("quantityUnit", query.variant.quantityUnit, candidate.variant.quantityUnit)
        ]
        var evidence: [String] = [], conflicts: [String] = []
        for (name, expected, actual) in fields where expected != nil {
            guard let actual else { continue }
            normalized(expected!) == normalized(actual) ? evidence.append(name) : conflicts.append(name)
        }
        if query.variant.condition != .unknown, candidate.variant.condition != .unknown,
           query.variant.condition != candidate.variant.condition { conflicts.append("condition") }
        if let expected = query.variant.quantity, let actual = candidate.variant.quantity,
           expected != actual { conflicts.append("quantity") }

        let exactGTIN = equalIdentifier(query.gtin, candidate.gtin)
        let exactSKU = equalIdentifier(query.sku, candidate.sku)
        if !conflicts.isEmpty { return .init(level: .approximate, evidence: evidence, conflicts: conflicts) }
        if exactGTIN { evidence.insert("gtin", at: 0); return .init(level: .exact, evidence: evidence, conflicts: []) }
        if exactSKU, sameCore(query, candidate) { evidence.insert("sku", at: 0); return .init(level: .exact, evidence: evidence, conflicts: []) }
        if sameCore(query, candidate), !evidence.isEmpty { return .init(level: .compatible, evidence: evidence, conflicts: []) }
        return .init(level: .unrelated, evidence: evidence, conflicts: [])
    }

    private func sameCore(_ a: ProductIdentity, _ b: ProductIdentity) -> Bool {
        normalized(a.productType) == normalized(b.productType)
            && optionalEqual(a.brand, b.brand) && optionalEqual(a.model, b.model)
    }
    private func optionalEqual(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b else { return true }
        return normalized(a) == normalized(b)
    }
    private func equalIdentifier(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b else { return false }
        return normalized(a) == normalized(b)
    }
    private func normalized(_ value: String) -> String {
        String(value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .filter { $0.isLetter || $0.isNumber })
    }
}
