import Foundation

enum LocalServiceCategory: String, Codable, CaseIterable, Sendable {
    case towTruck, taxi, courier, plumber, electrician, cleaning, locksmith, mechanic
    case carService, carRental, tireService, dentist, doctor, vet, delivery, repair, other

    var placeCategory: PlaceCategory {
        switch self {
        case .towTruck: .tow
        case .carService, .mechanic: .carService
        case .carRental: .other
        case .tireService: .tireService
        case .dentist: .dentist
        case .doctor: .clinic
        case .vet: .vet
        case .repair, .plumber, .electrician, .locksmith: .repair
        default: .other
        }
    }
}

struct LocalServiceRequest: Equatable, Sendable {
    let category: LocalServiceCategory
    let location: ValidatedLocation
    var radiusMeters: Double = 10_000
    var limit = 12

    init(command: StructuredCommand, location: ValidatedLocation) throws {
        guard command.intent == .serviceSearch,
              let raw = command.entities["serviceCategory"],
              let category = LocalServiceCategory(rawValue: raw) else { throw LocalServiceError.invalidRequest }
        self.category = category; self.location = location
    }

    func placeQuery() throws -> PlaceQuery {
        guard location.isSafeForLocationActions, (100...50_000).contains(radiusMeters), (1...20).contains(limit) else {
            throw LocalServiceError.unsafeOrUnboundedLocation
        }
        return try PlaceQuery(text: searchText, category: category.placeCategory, location: location,
                              radiusMeters: radiusMeters, limit: limit).validated()
    }

    private var searchText: String {
        switch category {
        case .towTruck: "tow truck"
        case .carService: "car service"
        case .carRental: "car rental"
        case .tireService: "tire service"
        default: category.rawValue
        }
    }
}

enum ServiceAvailabilityEvidence: Equatable, Sendable {
    case verifiedAvailable(source: String, timestamp: Date)
    case verifiedUnavailable(source: String, timestamp: Date)
    case unverified
}

struct LocalServiceOffer: Equatable, Sendable {
    let place: Place
    var availability: ServiceAvailabilityEvidence = .unverified
    var quotedPrice: Money?
    var exactBookingURL: URL?
}

enum ServiceHandoffKind: String, Equatable, Sendable { case directOrder, phone, officialWebsite, navigation }

struct ServiceHandoff: Equatable, Sendable {
    let kind: ServiceHandoffKind
    let destination: URL
    let claimsAvailability: Bool
}

enum LocalServiceError: Error, Equatable, Sendable {
    case invalidRequest, unsafeOrUnboundedLocation, invalidDestination, noUsefulFallback
}

struct LocalServiceHandoffPlanner: Sendable {
    func handoff(for offer: LocalServiceOffer) throws -> ServiceHandoff {
        if case .verifiedAvailable = offer.availability, let url = offer.exactBookingURL,
           isExactHTTPS(url) {
            return .init(kind: .directOrder, destination: url, claimsAvailability: true)
        }
        if let phone = offer.place.phone, let url = telephoneURL(phone) {
            return .init(kind: .phone, destination: url, claimsAvailability: false)
        }
        if let website = offer.place.officialWebsite, isExactHTTPS(website) {
            return .init(kind: .officialWebsite, destination: website, claimsAvailability: false)
        }
        guard (-90...90).contains(offer.place.latitude), (-180...180).contains(offer.place.longitude),
              var components = URLComponents(string: "https://maps.apple.com/") else {
            throw LocalServiceError.noUsefulFallback
        }
        components.queryItems = [.init(name: "daddr", value: "\(offer.place.latitude),\(offer.place.longitude)")]
        guard let url = components.url else { throw LocalServiceError.invalidDestination }
        return .init(kind: .navigation, destination: url, claimsAvailability: false)
    }

    private func isExactHTTPS(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host != nil && !url.path.isEmpty && url.path != "/"
    }

    private func telephoneURL(_ raw: String) -> URL? {
        let value = raw.filter { $0.isNumber || $0 == "+" }
        guard value.filter(\.isNumber).count >= 7 else { return nil }
        return URL(string: "tel:\(value)")
    }
}
