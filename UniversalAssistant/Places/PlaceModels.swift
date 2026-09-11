import Foundation

enum PlaceCategory: String, Codable, CaseIterable, Sendable {
    case cafe, restaurant, shop, supermarket, mall, pharmacy, hospital, clinic, dentist, vet
    case fuel, evCharging, parking, bank, atm, post, hotel, carService, tireService, carWash, tow
    case beauty, repair, government, police, other
}
enum PlaceVerification: String, Codable, Sendable { case providerReturned, providerVerified, unverified }

struct Place: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let providerID: String?
    let name: String
    let category: PlaceCategory
    let latitude: Double
    let longitude: Double
    var address: String?
    var distanceMeters: Double?
    var travelTimeSeconds: TimeInterval?
    var phone: String?
    var officialWebsite: URL?
    var rating: Double?
    var reviewCount: Int?
    var openingHours: String?
    var isOpenNow: Bool?
    var priceLevel: Int?
    let source: String
    let timestamp: Date
    let verification: PlaceVerification
    var confidence: Double? = nil

    func freshness(now: Date = .now, recentFor: TimeInterval = 900) -> PlaceFreshness {
        let age = now.timeIntervalSince(timestamp)
        if age < -5 { return .unknown }
        return age <= recentFor ? .recent : .stale
    }
}

enum PlaceFreshness: String, Equatable, Codable, Sendable { case recent, stale, unknown }

struct PlaceQuery: Equatable, Sendable {
    let text: String
    let category: PlaceCategory?
    let location: ValidatedLocation
    var radiusMeters: Double = 5_000
    var limit: Int = 20

    func validated() throws -> Self {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PlaceProviderError.invalidQuery }
        guard location.isSafeForLocationActions else { throw PlaceProviderError.unsafeLocation }
        guard (100...50_000).contains(radiusMeters), (1...50).contains(limit) else { throw PlaceProviderError.invalidBounds }
        return self
    }
}

enum PlaceProviderError: Error, Equatable { case invalidQuery, unsafeLocation, invalidBounds }
protocol PlaceProvider: Sendable {
    var providerID: String { get }
    func search(_ query: PlaceQuery) async throws -> [Place]
}

struct PlaceDeduplicator: Sendable {
    func deduplicate(_ places: [Place]) -> [Place] {
        var output: [Place] = []
        for place in places {
            if let index = output.firstIndex(where: { reliableDuplicate($0, place) }) {
                output[index] = richer(output[index], place)
            } else { output.append(place) }
        }
        return output
    }

    private func reliableDuplicate(_ a: Place, _ b: Place) -> Bool {
        if a.source == b.source {
            guard let x = a.providerID, let y = b.providerID else { return false }
            return x == y
        }
        return normalize(a.name) == normalize(b.name) && distance(a, b) <= 30 && a.category == b.category
    }
    private func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^\p{L}\p{N}]"#, with: "", options: .regularExpression)
    }
    private func distance(_ a: Place, _ b: Place) -> Double {
        let x = (b.longitude - a.longitude) * cos((a.latitude + b.latitude) * .pi / 360)
        let y = b.latitude - a.latitude
        return sqrt(x * x + y * y) * .pi / 180 * 6_371_000
    }
    private func richer(_ a: Place, _ b: Place) -> Place {
        let score: (Place) -> Int = { [$0.address, $0.phone, $0.officialWebsite?.absoluteString, $0.openingHours].compactMap { $0 }.count }
        return score(b) > score(a) ? b : a
    }
}

struct PlaceProximityOrdering: Sendable {
    func nearestFirst(_ places: [Place], from origin: ValidatedLocation) -> [Place] {
        nearestFirst(places.map { place in
            var value = place
            // The typed origin is authoritative. Provider distances may be
            // absent, stale, or calculated from a provider-default region.
            value.distanceMeters = Self.distance(fromLatitude: origin.sample.latitude, longitude: origin.sample.longitude, toLatitude: place.latitude, longitude: place.longitude)
            return value
        })
    }

    func nearestFirst(_ places: [Place]) -> [Place] {
        places.enumerated().sorted { lhs, rhs in
            switch (lhs.element.distanceMeters, rhs.element.distanceMeters) {
            case let (l?, r?): return l == r ? lhs.offset < rhs.offset : l < r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    private static func distance(fromLatitude latitude: Double, longitude: Double, toLatitude destinationLatitude: Double, longitude destinationLongitude: Double) -> Double {
        let radius = 6_371_000.0
        let firstLatitude = latitude * .pi / 180, secondLatitude = destinationLatitude * .pi / 180
        let latitudeDelta = (destinationLatitude - latitude) * .pi / 180
        let longitudeDelta = (destinationLongitude - longitude) * .pi / 180
        let haversine = sin(latitudeDelta / 2) * sin(latitudeDelta / 2) + cos(firstLatitude) * cos(secondLatitude) * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        return radius * 2 * atan2(sqrt(haversine), sqrt(1 - haversine))
    }
}

struct PlaceRanker: Sendable {
    func rank(_ places: [Place], query: PlaceQuery) -> [Place] {
        places.enumerated().sorted { lhs, rhs in
            let l = score(lhs.element, query), r = score(rhs.element, query)
            return l == r ? lhs.offset < rhs.offset : l > r
        }.map(\.element)
    }
    private func score(_ place: Place, _ query: PlaceQuery) -> Double {
        var value = 0.0
        let needle = query.text.lowercased(), name = place.name.lowercased()
        if name == needle { value += 100 } else if name.contains(needle) { value += 50 }
        if query.category == place.category { value += 30 }
        if place.isOpenNow == true { value += 15 } else if place.isOpenNow == false { value -= 20 }
        if let travelTime = place.travelTimeSeconds { value += max(0, 24 - travelTime / 90) }
        else if let distance = place.distanceMeters { value += max(0, 20 - distance / 250) }
        if let rating = place.rating, let count = place.reviewCount, count > 0 { value += min(10, rating * log10(Double(count) + 1)) }
        if place.verification == .providerVerified { value += 5 }
        if let confidence = place.confidence { value += max(0, min(1, confidence)) * 5 }
        return value
    }
}
