@preconcurrency import MapKit
import Foundation

struct MapKitPlaceProvider: PlaceProvider {
    let providerID = "apple-mapkit"

    func search(_ input: PlaceQuery) async throws -> [Place] {
        let query = try input.validated()
        let center = CLLocationCoordinate2D(latitude: query.location.sample.latitude, longitude: query.location.sample.longitude)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query.text
        request.region = MKCoordinateRegion(center: center, latitudinalMeters: query.radiusMeters * 2, longitudinalMeters: query.radiusMeters * 2)
        request.resultTypes = .pointOfInterest
        let response = try await MKLocalSearch(request: request).start()
        let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return response.mapItems.prefix(query.limit).map { item in
            // MKMapItem.location only exists in a newer SDK than the one this
            // project builds with, so the placemark (available since iOS 18)
            // is the portable path.
            let location: CLLocation = item.placemark.location ?? origin
            let address: String? = item.placemark.title
            let rawID = item.identifier?.rawValue
            return Place(
                id: rawID ?? "mapkit:\(location.coordinate.latitude):\(location.coordinate.longitude):\(item.name ?? "place")",
                providerID: rawID, name: item.name ?? "", category: Self.category(item.pointOfInterestCategory),
                latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                address: address, distanceMeters: origin.distance(from: location), phone: item.phoneNumber,
                officialWebsite: item.url, source: providerID, timestamp: .now, verification: .providerReturned
            )
        }.filter { !$0.name.isEmpty }
    }

    private static func category(_ value: MKPointOfInterestCategory?) -> PlaceCategory {
        switch value {
        case .cafe: .cafe
        case .restaurant: .restaurant
        case .store: .shop
        case .pharmacy: .pharmacy
        case .hospital: .hospital
        case .hotel: .hotel
        case .gasStation: .fuel
        case .evCharger: .evCharging
        case .parking: .parking
        case .bank: .bank
        case .atm: .atm
        case .postOffice: .post
        case .police: .police
        default: .other
        }
    }
}
