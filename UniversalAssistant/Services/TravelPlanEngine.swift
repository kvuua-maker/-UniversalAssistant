import Foundation

enum IntercityTravelMode: String, Codable, CaseIterable, Sendable {
    case car, rail, coach, flight, ferry
}

enum TravelEvidenceLevel: String, Codable, Sendable {
    case scheduled, providerConfirmed, realTime
}

struct TravelJourney: Identifiable, Equatable, Sendable {
    let id: String
    let providerID: String
    let mode: IntercityTravelMode
    let origin: String
    let destination: String
    let departure: Date
    let arrival: Date
    var price: Money?
    var transfers: Int
    var availability: VerifiedServiceAvailability
    let evidenceLevel: TravelEvidenceLevel
    let observedAt: Date
    var originAccess: TransportOption?
    var destinationAccess: TransportOption?
    var exactHandoffURL: URL?

    var duration: TimeInterval { arrival.timeIntervalSince(departure) }

    var isStructurallyValid: Bool {
        !id.isEmpty && !providerID.isEmpty &&
        !origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        arrival > departure && transfers >= 0
    }
}

struct TravelWeatherContext: Equatable, Sendable {
    let destination: String
    let summary: String
    let source: String
    let observedAt: Date
}

struct TravelPlanRequest: Equatable, Sendable {
    let origin: String
    let destination: String
    var departureNotBefore: Date?
    let arrivalNotAfter: Date
    var allowedModes: Set<IntercityTravelMode> = Set(IntercityTravelMode.allCases)
    var maximumTotal: Money?
    var maximumTransfers: Int?
    var requiresVerifiedAvailability = false
    var needsAccommodation = false
}

enum TravelPlanCoverage: String, Equatable, Sendable {
    case complete, partial
}

struct TravelPlan: Identifiable, Equatable, Sendable {
    let id: String
    let journey: TravelJourney
    var hotel: HotelOffer?
    var weather: TravelWeatherContext?
    var knownTotal: Money?
    let coverage: TravelPlanCoverage
    let missingContext: [String]
}

enum TravelPlanError: Error, Equatable, Sendable {
    case invalidRequest
    case noFeasibleJourney
}

struct TravelPlanEngine: Sendable {
    var maximumEvidenceAge: TimeInterval = 10 * 60
    var maximumWeatherAge: TimeInterval = 60 * 60

    func plan(
        request: TravelPlanRequest,
        journeys: [TravelJourney],
        hotels: [HotelOffer] = [],
        weather: TravelWeatherContext? = nil,
        now: Date = .now
    ) throws -> [TravelPlan] {
        guard valid(request), maximumEvidenceAge > 0, maximumWeatherAge > 0 else {
            throw TravelPlanError.invalidRequest
        }

        let matchingHotels = hotels.filter { hotel in
            hotel.locationLabel.caseInsensitiveCompare(request.destination) == .orderedSame &&
            hotel.availability.state != .unavailable
        }
        let freshWeather = weather.flatMap { context -> TravelWeatherContext? in
            guard context.destination.caseInsensitiveCompare(request.destination) == .orderedSame,
                  !context.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  isFresh(context.observedAt, maximumAge: maximumWeatherAge, now: now) else { return nil }
            return context
        }

        let candidates = journeys.enumerated().compactMap { index, journey -> (Int, TravelPlan)? in
            guard journey.isStructurallyValid,
                  journey.origin.caseInsensitiveCompare(request.origin) == .orderedSame,
                  journey.destination.caseInsensitiveCompare(request.destination) == .orderedSame,
                  request.allowedModes.contains(journey.mode),
                  journey.arrival <= request.arrivalNotAfter,
                  request.departureNotBefore.map({ journey.departure >= $0 }) ?? true,
                  request.maximumTransfers.map({ journey.transfers <= $0 }) ?? true,
                  journey.availability != .unavailable,
                  isFresh(journey.observedAt, maximumAge: maximumEvidenceAge, now: now) else { return nil }
            if request.requiresVerifiedAvailability {
                guard journey.availability == .available,
                      journey.evidenceLevel != .scheduled else { return nil }
            }

            let hotel = request.needsAccommodation ? bestHotel(matchingHotels, now: now) : nil
            var missing: [String] = []
            if journey.originAccess == nil { missing.append("origin_access") }
            if journey.destinationAccess == nil { missing.append("destination_access") }
            if request.needsAccommodation && hotel == nil { missing.append("accommodation") }
            if freshWeather == nil { missing.append("weather") }
            let hotelTotal = hotel.flatMap { verifiedHotelTotal($0, now: now) }
            let total = combinedTotal(journey.price, hotelTotal)
            if let budget = request.maximumTotal {
                if request.needsAccommodation && hotelTotal == nil { return nil }
                guard let total, total.currency == budget.currency, total.amount <= budget.amount else { return nil }
            }
            return (index, .init(
                id: journey.id, journey: journey, hotel: hotel, weather: freshWeather,
                knownTotal: total, coverage: missing.isEmpty ? .complete : .partial,
                missingContext: missing
            ))
        }
        guard !candidates.isEmpty else { throw TravelPlanError.noFeasibleJourney }
        return candidates.sorted { left, right in
            if left.1.journey.arrival != right.1.journey.arrival {
                return left.1.journey.arrival < right.1.journey.arrival
            }
            if left.1.coverage != right.1.coverage { return left.1.coverage == .complete }
            if left.1.journey.transfers != right.1.journey.transfers {
                return left.1.journey.transfers < right.1.journey.transfers
            }
            return left.0 < right.0
        }.map { $0.1 }
    }

    private func valid(_ request: TravelPlanRequest) -> Bool {
        !request.origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !request.destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        request.origin.caseInsensitiveCompare(request.destination) != .orderedSame &&
        request.arrivalNotAfter > (request.departureNotBefore ?? .distantPast) &&
        !request.allowedModes.isEmpty &&
        (request.maximumTotal.map { $0.amount >= 0 } ?? true) &&
        (request.maximumTransfers.map { $0 >= 0 } ?? true)
    }

    private func isFresh(_ date: Date, maximumAge: TimeInterval, now: Date) -> Bool {
        let age = now.timeIntervalSince(date)
        return age >= -60 && age <= maximumAge
    }

    private func bestHotel(_ hotels: [HotelOffer], now: Date) -> HotelOffer? {
        hotels.enumerated().filter { _, hotel in
            guard let observed = hotel.availability.observedAt,
                  isFresh(observed, maximumAge: maximumEvidenceAge, now: now) else { return false }
            return hotel.availability.state == .liveConfirmed || hotel.availability.state == .providerConfirmed
        }.sorted { left, right in
            switch (left.element.price.knownTotal, right.element.price.knownTotal) {
            case let (lhs?, rhs?) where lhs.currency == rhs.currency && lhs.amount != rhs.amount:
                return lhs.amount < rhs.amount
            default: return left.offset < right.offset
            }
        }.first?.element
    }

    private func verifiedHotelTotal(_ hotel: HotelOffer, now: Date) -> Money? {
        guard hotel.price.includesMandatoryFees,
              let total = hotel.price.knownTotal,
              let observed = hotel.price.observedAt,
              isFresh(observed, maximumAge: maximumEvidenceAge, now: now) else { return nil }
        return total
    }

    private func combinedTotal(_ journey: Money?, _ hotel: Money?) -> Money? {
        switch (journey, hotel) {
        case let (journey?, hotel?) where journey.currency == hotel.currency:
            return .init(amount: journey.amount + hotel.amount, currency: journey.currency)
        case let (journey?, nil): return journey
        case let (nil, hotel?): return hotel
        default: return nil
        }
    }
}
