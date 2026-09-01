import Foundation

enum ComparisonMode: String, Codable, CaseIterable, Sendable {
    case cheapest, fastest, optimal, comfort, largeVehicle, childSeat, petFriendly, luggage
}

enum VerifiedServiceAvailability: String, Codable, Sendable { case available, unavailable, unknown }

protocol ComparableServiceOffer: Identifiable, Sendable {
    var providerID: String { get }
    var price: Money? { get }
    var pickupWaitSeconds: TimeInterval? { get }
    var availability: VerifiedServiceAvailability { get }
    var evidenceTimestamp: Date? { get }
}

enum RideClass: String, Codable, CaseIterable, Sendable { case economy, comfort, premium, van, other }

struct RideCapabilities: OptionSet, Equatable, Sendable {
    let rawValue: Int
    static let childSeat = Self(rawValue: 1 << 0)
    static let petFriendly = Self(rawValue: 1 << 1)
    static let largeVehicle = Self(rawValue: 1 << 2)
    static let luggage = Self(rawValue: 1 << 3)
}

struct RideOffer: ComparableServiceOffer, Equatable, Sendable {
    let id: String
    let providerID: String
    var price: Money?
    var pickupWaitSeconds: TimeInterval?
    var estimatedArrival: Date?
    var availability: VerifiedServiceAvailability
    var rideClass: RideClass?
    var capabilities: RideCapabilities = []
    var evidenceTimestamp: Date?
    let exactHandoffURL: URL

    func isFresh(now: Date, maximumAge: TimeInterval) -> Bool {
        guard let evidenceTimestamp else { return false }
        let age = now.timeIntervalSince(evidenceTimestamp)
        return age >= -60 && age <= maximumAge
    }
}

struct RideComparisonRequest: Equatable, Sendable {
    let mode: ComparisonMode
    var maximumPrice: Money?
    var maximumWaitSeconds: TimeInterval?
    var requiredCapabilities: RideCapabilities = []
}

enum RideComparisonError: Error, Equatable, Sendable {
    case invalidConstraint, noVerifiedOffers, incomparableCurrencies
}

struct RideComparisonEngine: Sendable {
    var maximumEvidenceAge: TimeInterval = 5 * 60

    func compare(_ offers: [RideOffer], request: RideComparisonRequest, now: Date = .now) throws -> [RideOffer] {
        guard maximumEvidenceAge > 0,
              request.maximumWaitSeconds.map({ $0 >= 0 }) ?? true,
              request.maximumPrice.map({ $0.amount >= 0 }) ?? true else { throw RideComparisonError.invalidConstraint }

        var candidates = offers.filter {
            $0.isFresh(now: now, maximumAge: maximumEvidenceAge) &&
            $0.availability == .available &&
            $0.capabilities.intersection(request.requiredCapabilities) == request.requiredCapabilities
        }
        if let maximumWait = request.maximumWaitSeconds {
            candidates = candidates.filter { $0.pickupWaitSeconds.map { $0 <= maximumWait } ?? false }
        }
        if let budget = request.maximumPrice {
            candidates = candidates.filter { offer in
                guard let price = offer.price, price.currency == budget.currency else { return false }
                return price.amount <= budget.amount
            }
        }
        guard !candidates.isEmpty else { throw RideComparisonError.noVerifiedOffers }
        if request.mode == .cheapest {
            let currencies = Set(candidates.compactMap { $0.price?.currency })
            guard currencies.count <= 1 else { throw RideComparisonError.incomparableCurrencies }
        }
        return candidates.enumerated().sorted { left, right in
            let comparison = compare(left.element, right.element, mode: request.mode)
            return comparison == .orderedSame ? left.offset < right.offset : comparison == .orderedAscending
        }.map(\.element)
    }

    private func compare(_ lhs: RideOffer, _ rhs: RideOffer, mode: ComparisonMode) -> ComparisonResult {
        switch mode {
        case .cheapest:
            compareOptional(lhs.price?.amount, rhs.price?.amount)
        case .fastest:
            compareOptional(lhs.pickupWaitSeconds, rhs.pickupWaitSeconds)
        case .optimal:
            compareOptional(optimalScore(lhs), optimalScore(rhs))
        case .comfort:
            compareOptional(classScore(rhs.rideClass), classScore(lhs.rideClass))
        case .largeVehicle, .childSeat, .petFriendly, .luggage:
            compareOptional(lhs.pickupWaitSeconds, rhs.pickupWaitSeconds)
        }
    }

    private func optimalScore(_ offer: RideOffer) -> Decimal? {
        guard let price = offer.price, let wait = offer.pickupWaitSeconds else { return nil }
        return price.amount + Decimal(wait / 60)
    }

    private func classScore(_ value: RideClass?) -> Int? {
        switch value { case .premium: 4; case .comfort: 3; case .van: 2; case .economy: 1; case .other: 0; case nil: nil }
    }

    private func compareOptional<T: Comparable>(_ lhs: T?, _ rhs: T?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (left?, right?): left == right ? .orderedSame : (left < right ? .orderedAscending : .orderedDescending)
        case (_?, nil): .orderedAscending
        case (nil, _?): .orderedDescending
        case (nil, nil): .orderedSame
        }
    }
}
