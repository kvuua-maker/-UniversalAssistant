import Foundation

struct RestaurantSearchRequest: Equatable, Sendable {
    var cuisine: String?
    var maximumPriceLevel: Int?
    var minimumRating: Double?
    var maximumDistanceMeters: Double?
    var openNow = false
    var partySize: Int?
    var interval: DateInterval?
    var dietaryPreferences: Set<String> = []

    func validated() throws -> Self {
        guard maximumPriceLevel.map({ (1...4).contains($0) }) ?? true,
              minimumRating.map({ (0...5).contains($0) }) ?? true,
              maximumDistanceMeters.map({ $0 > 0 && $0 <= 50_000 }) ?? true,
              partySize.map({ (1...50).contains($0) }) ?? true,
              interval.map({ $0.duration > 0 }) ?? true
        else { throw RestaurantDiscoveryError.invalidRequest }
        return self
    }
}

struct RestaurantOffer: Identifiable, Equatable, Sendable {
    let id: String
    let place: Place
    let cuisines: Set<String>
    let dietaryOptions: Set<String>
    let evidenceTimestamp: Date
    let sourceReference: String
    var officialBookingURL: URL?

    func matches(_ request: RestaurantSearchRequest, now: Date, maximumEvidenceAge: TimeInterval) -> Bool {
        let age = now.timeIntervalSince(evidenceTimestamp)
        guard age >= -60, age <= maximumEvidenceAge, !sourceReference.isEmpty,
              request.minimumRating.map({ (place.rating ?? -1) >= $0 }) ?? true,
              request.maximumDistanceMeters.map({ maximum in place.distanceMeters.map({ $0 <= maximum }) ?? false }) ?? true,
              request.maximumPriceLevel.map({ (place.priceLevel ?? .max) <= $0 }) ?? true,
              (!request.openNow || place.isOpenNow == true)
        else { return false }
        if let cuisine = request.cuisine?.lowercased(),
           !cuisines.map({ $0.lowercased() }).contains(cuisine) { return false }
        let normalizedDiet = Set(dietaryOptions.map { $0.lowercased() })
        return request.dietaryPreferences.map({ $0.lowercased() }).allSatisfy(normalizedDiet.contains)
    }
}

struct RestaurantReservationSlot: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let providerID: String
    let restaurantID: String
    let interval: DateInterval
    let partySize: Int
    let availabilityVerified: Bool
    let observedAt: Date
    let sourceReference: String
}

struct RestaurantReservation: Equatable, Codable, Sendable {
    let id: String
    let providerID: String
    let slotID: String
    let state: AppointmentBookingState
    let providerReference: String
    let observedAt: Date
}

protocol ReservationProvider: Sendable {
    var providerID: String { get }
    func availability(restaurantID: String, partySize: Int, interval: DateInterval) async throws -> [RestaurantReservationSlot]
    func book(slotID: String) async throws -> RestaurantReservation
}

enum RestaurantBookingOutcome: Equatable, Sendable {
    case confirmed(RestaurantReservation)
    case officialHandoff(URL)
    case phone(URL)
    case navigation(URL)
}

enum RestaurantDiscoveryError: Error, Equatable, Sendable {
    case invalidRequest, unverifiedSlot, confirmationRequired, unverifiedBooking, noUsefulFallback
}

struct RestaurantDiscoveryEngine: Sendable {
    let providers: [any ReservationProvider]
    var maximumEvidenceAge: TimeInterval = 15 * 60

    func filter(_ offers: [RestaurantOffer], request: RestaurantSearchRequest, now: Date = .now) throws -> [RestaurantOffer] {
        let request = try request.validated()
        return offers.filter { $0.matches(request, now: now, maximumEvidenceAge: maximumEvidenceAge) }
            .sorted {
                if $0.place.distanceMeters != $1.place.distanceMeters {
                    return ($0.place.distanceMeters ?? .greatestFiniteMagnitude) < ($1.place.distanceMeters ?? .greatestFiniteMagnitude)
                }
                return $0.id < $1.id
            }
    }

    func availability(for offer: RestaurantOffer, request: RestaurantSearchRequest, now: Date = .now) async -> [RestaurantReservationSlot] {
        guard let partySize = request.partySize, let interval = request.interval else { return [] }
        var result: [RestaurantReservationSlot] = []
        await withTaskGroup(of: [RestaurantReservationSlot].self) { group in
            for provider in providers.prefix(6) {
                group.addTask { (try? await provider.availability(restaurantID: offer.id, partySize: partySize, interval: interval)) ?? [] }
            }
            for await slots in group {
                result += slots.filter {
                    $0.restaurantID == offer.id && $0.partySize == partySize && $0.availabilityVerified &&
                    !$0.sourceReference.isEmpty && interval.contains($0.interval.start) && $0.interval.end <= interval.end &&
                    now.timeIntervalSince($0.observedAt) >= -60 && now.timeIntervalSince($0.observedAt) <= maximumEvidenceAge
                }
            }
        }
        return result.sorted { $0.interval.start < $1.interval.start }
    }

    func book(_ slot: RestaurantReservationSlot, confirmed: Bool, now: Date = .now) async throws -> RestaurantBookingOutcome {
        guard slot.availabilityVerified, !slot.sourceReference.isEmpty,
              now.timeIntervalSince(slot.observedAt) >= -60,
              now.timeIntervalSince(slot.observedAt) <= maximumEvidenceAge
        else { throw RestaurantDiscoveryError.unverifiedSlot }
        guard confirmed else { throw RestaurantDiscoveryError.confirmationRequired }
        guard let provider = providers.first(where: { $0.providerID == slot.providerID }) else {
            throw RestaurantDiscoveryError.unverifiedBooking
        }
        let booking = try await provider.book(slotID: slot.id)
        guard booking.providerID == slot.providerID, booking.slotID == slot.id,
              booking.state == .confirmed, !booking.providerReference.isEmpty
        else { throw RestaurantDiscoveryError.unverifiedBooking }
        return .confirmed(booking)
    }

    func fallback(for offer: RestaurantOffer) throws -> RestaurantBookingOutcome {
        if let url = offer.officialBookingURL, exactHTTPS(url) { return .officialHandoff(url) }
        if let phone = offer.place.phone {
            let normalized = phone.filter { $0.isNumber || $0 == "+" }
            if normalized.filter(\.isNumber).count >= 7, let url = URL(string: "tel:\(normalized)") { return .phone(url) }
        }
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [.init(name: "daddr", value: "\(offer.place.latitude),\(offer.place.longitude)")]
        guard let url = components?.url else { throw RestaurantDiscoveryError.noUsefulFallback }
        return .navigation(url)
    }

    private func exactHTTPS(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host != nil && !url.path.isEmpty && url.path != "/"
    }
}
