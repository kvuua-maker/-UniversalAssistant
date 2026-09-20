import Foundation

struct OSMFuelSnapshot: Codable, Sendable {
    let generatedAt: Date
    let sourceURL: URL
    let license: String
    let stations: [Station]

    struct Station: Codable, Sendable {
        let id: String
        let name: String?
        let operatorName: String?
        let latitude: Double
        let longitude: Double
        let address: String?
        let phone: String?
        let website: URL?
        let openingHours: String?
        let fuels: Set<FuelConstraint>
    }
}

struct OSMFuelPOIProvider: PlaceProvider {
    let providerID = "openstreetmap-fuel-snapshot"
    private let snapshot: OSMFuelSnapshot

    init(bundle: Bundle = .main) {
        if let url = bundle.url(forResource: "ukraine-fuel-pois", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder.iso8601.decode(OSMFuelSnapshot.self, from: data) {
            snapshot = decoded
        } else {
            snapshot = .init(
                generatedAt: .distantPast,
                sourceURL: URL(string: "https://download.geofabrik.de/europe/ukraine.html")!,
                license: "© OpenStreetMap contributors · ODbL 1.0",
                stations: []
            )
        }
    }

    init(snapshot: OSMFuelSnapshot) { self.snapshot = snapshot }

    func search(_ query: PlaceQuery) async throws -> [Place] {
        guard query.category == .fuel else { return [] }
        let origin = query.location.sample
        return snapshot.stations.lazy
            .filter { station in
                query.fuelConstraint.map(station.fuels.contains) ?? true
            }
            .map { station in
                Place(
                    id: "osm:\(station.id)", providerID: station.id,
                    name: station.name ?? station.operatorName ?? "АЗС",
                    category: .fuel, latitude: station.latitude, longitude: station.longitude,
                    address: station.address,
                    distanceMeters: Self.distance(origin.latitude, origin.longitude, station.latitude, station.longitude),
                    phone: station.phone, officialWebsite: station.website,
                    openingHours: station.openingHours, source: "OpenStreetMap",
                    timestamp: snapshot.generatedAt, verification: .providerReturned,
                    confidence: station.fuels.isEmpty ? 0.65 : 0.9,
                    fuelCapabilities: station.fuels,
                    attribution: snapshot.license
                )
            }
            .filter { ($0.distanceMeters ?? .infinity) <= query.radiusMeters }
            .sorted { ($0.distanceMeters ?? .infinity) < ($1.distanceMeters ?? .infinity) }
            .prefix(query.limit)
            .map { $0 }
    }

    private static func distance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let radius = 6_371_000.0
        let first = lat1 * .pi / 180, second = lat2 * .pi / 180
        let dLat = (lat2 - lat1) * .pi / 180, dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(first) * cos(second) * sin(dLon / 2) * sin(dLon / 2)
        return radius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
