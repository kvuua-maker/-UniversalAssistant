import Foundation

struct Money: Equatable, Codable, Sendable {
    let amount: Decimal
    let currency: String

    func adding(_ other: Money) -> Money? {
        guard currency == other.currency else { return nil }
        return .init(amount: amount + other.amount, currency: currency)
    }
}

enum OfferAvailability: String, Codable, Sendable { case inStock, outOfStock, preorder, unknown }
enum CostKnowledge: String, Codable, Sendable { case known, estimated, unknown }

struct CostComponent: Equatable, Codable, Sendable {
    let value: Money?
    let knowledge: CostKnowledge
}

struct OfferTotalCost: Equatable, Codable, Sendable {
    let item: Money
    let shipping: CostComponent
    let tax: CostComponent
    let duties: CostComponent
    let requiredOther: CostComponent

    var calculableTotal: Money? {
        let components = [shipping, tax, duties, requiredOther]
        guard components.allSatisfy({ $0.knowledge != .unknown && $0.value != nil }) else { return nil }
        return components.compactMap(\.value).reduce(item) { $0.adding($1) ?? $0 }
    }
}

struct SellerSummary: Equatable, Codable, Sendable {
    let id: String
    let name: String
    var rating: Double?
    var reviewCount: Int?
    var isOfficialStore: Bool?
    var buyerProtection: String?
    var returns: String?
    var warranty: String?
}

struct NormalizedOffer: Identifiable, Equatable, Sendable {
    let id: String
    let providerID: String
    let providerOfferID: String
    let identity: ProductIdentity
    let identityMatch: ProductIdentityMatch
    let seller: SellerSummary
    let availability: OfferAvailability
    let cost: OfferTotalCost
    var deliversToUkraine: Bool?
    var deliveryETA: DateInterval?
    let exactPurchaseURL: URL
    let sourceTimestamp: Date
    let fetchedAt: Date
    var affiliateAttributionSupported: Bool

    func isFresh(now: Date = .now, maximumAge: TimeInterval = 15 * 60) -> Bool {
        now.timeIntervalSince(sourceTimestamp) >= 0 && now.timeIntervalSince(sourceTimestamp) <= maximumAge
    }
}

struct OfferDeduplicator: Sendable {
    func deduplicate(_ offers: [NormalizedOffer]) -> [NormalizedOffer] {
        var seen: Set<String> = [], result: [NormalizedOffer] = []
        for offer in offers {
            let key = "\(offer.providerID)|\(offer.providerOfferID)|\(offer.seller.id)"
            if seen.insert(key).inserted { result.append(offer) }
        }
        return result
    }
}

struct OfferRanker: Sendable {
    func rank(_ offers: [NormalizedOffer], now: Date = .now) -> [NormalizedOffer] {
        offers.enumerated().sorted {
            let left = score($0.element, now: now), right = score($1.element, now: now)
            return left == right ? $0.offset < $1.offset : left > right
        }.map(\.element)
    }

    private func score(_ offer: NormalizedOffer, now: Date) -> Decimal {
        var score = Decimal(offer.identityMatch.level.rawValue * 1_000)
        if offer.isFresh(now: now) { score += 200 }
        if offer.availability == .inStock { score += 150 }
        if offer.deliversToUkraine == true { score += 100 }
        if offer.seller.isOfficialStore == true { score += 60 }
        if offer.seller.buyerProtection != nil { score += 30 }
        if offer.seller.returns != nil { score += 20 }
        if offer.seller.warranty != nil { score += 20 }
        if let rating = offer.seller.rating { score += Decimal(rating * 10) }
        if let total = offer.cost.calculableTotal { score -= total.amount / 10_000 }
        return score
    }
}
