import Foundation
import Observation

enum CommerceOfferBadge: String, Equatable, Sendable {
    case bestTotalPrice
    case fastestDelivery
    case officialStore
}

struct CommerceOfferPresentation: Identifiable, Equatable, Sendable {
    let offer: NormalizedOffer
    let badges: [CommerceOfferBadge]

    var id: String { offer.id }

    var title: String {
        [offer.identity.brand, offer.identity.model]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .nilIfEmpty ?? offer.identity.productType
    }

    var variant: String? {
        let value = [
            offer.identity.variant.storage,
            offer.identity.variant.size,
            offer.identity.variant.color,
            offer.identity.variant.generation,
            offer.identity.variant.configuration,
            offer.identity.variant.region
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        return value.nilIfEmpty
    }

    var discountPercentage: Int? {
        guard let original = offer.originalItemPrice,
              original.currency == offer.cost.item.currency,
              original.amount > offer.cost.item.amount,
              original.amount > 0 else { return nil }
        let percent = (original.amount - offer.cost.item.amount) / original.amount * 100
        return NSDecimalNumber(decimal: percent).intValue
    }

    static func make(from offers: [NormalizedOffer]) -> [Self] {
        let calculatedTotals = offers.compactMap { offer in offer.cost.calculableTotal.map { (offer.id, $0) } }
        let currencies = Set(calculatedTotals.map { $0.1.currency })
        let totalCandidates = calculatedTotals.map { ($0.0, $0.1.amount) }
        let bestTotalID = currencies.count == 1 ? uniqueMinimum(totalCandidates) : nil
        let etaCandidates = offers.compactMap { offer in offer.deliveryETA.map { (offer.id, $0.end) } }
        let fastestID = uniqueMinimum(etaCandidates)

        return offers.map { offer in
            var badges: [CommerceOfferBadge] = []
            if offer.id == bestTotalID { badges.append(.bestTotalPrice) }
            if offer.id == fastestID { badges.append(.fastestDelivery) }
            if offer.seller.isOfficialStore == true { badges.append(.officialStore) }
            return .init(offer: offer, badges: badges)
        }
    }

    private static func uniqueMinimum<Value: Comparable>(_ values: [(String, Value)]) -> String? {
        guard let minimum = values.map(\.1).min() else { return nil }
        let matches = values.filter { $0.1 == minimum }
        return matches.count == 1 ? matches[0].0 : nil
    }
}

@MainActor
@Observable
final class CommerceResultsState {
    private(set) var offers: [CommerceOfferPresentation] = []
    private(set) var failures: [CommerceProviderFailure] = []
    private(set) var isComplete = false

    func apply(_ update: CommerceSearchUpdate) {
        let incoming = CommerceOfferPresentation.make(from: update.response.offers)
        let byID = Dictionary(uniqueKeysWithValues: incoming.map { ($0.id, $0) })
        var stable = offers.compactMap { byID[$0.id] }
        let existing = Set(stable.map(\.id))
        stable.append(contentsOf: incoming.filter { !existing.contains($0.id) })
        offers = stable
        failures = update.response.failures
        isComplete = update.isComplete
    }

    func reset() {
        offers = []
        failures = []
        isComplete = false
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
