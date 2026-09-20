import SwiftUI
import MapKit

struct PlaceResultsView: View {
    let places: [Place]

    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(places) { place in
                VStack(alignment: .leading, spacing: 10) {
                    Map(initialPosition: .region(.init(
                        center: .init(latitude: place.latitude, longitude: place.longitude),
                        span: .init(latitudeDelta: 0.012, longitudeDelta: 0.012)
                    ))) {
                        Marker(place.name, coordinate: .init(latitude: place.latitude, longitude: place.longitude))
                    }
                    .frame(height: 130)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .allowsHitTesting(false)

                    Text(place.name).font(.headline)
                    HStack(spacing: 8) {
                        if let distance = place.distanceMeters { Label(distanceText(distance), systemImage: "location.fill") }
                        if let isOpen = place.isOpenNow { Text(isOpen ? "Відчинено" : "Зачинено").foregroundStyle(isOpen ? .green : .secondary) }
                    }.font(.subheadline)
                    if let address = place.address { Text(address).font(.subheadline).foregroundStyle(.secondary) }
                    if !place.fuelCapabilities.isEmpty {
                        Text("Паливо: " + place.fuelCapabilities.map(displayName).sorted().joined(separator: " · "))
                            .font(.caption.weight(.semibold))
                    }
                    HStack {
                        if let url = appleMapsURL(place) { Link("Маршрут", destination: url).buttonStyle(.borderedProminent) }
                        Menu("Ще") {
                            if let url = googleMapsURL(place) { Link("Google Maps", destination: url) }
                            if let url = wazeURL(place) { Link("Waze", destination: url) }
                        }
                        .buttonStyle(.bordered)
                        if let phone = place.phone, let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                            Link("Подзвонити", destination: url).buttonStyle(.bordered)
                        }
                        if let url = place.officialWebsite { Link("Сайт", destination: url).buttonStyle(.bordered) }
                    }
                    if let attribution = place.attribution { Text(attribution).font(.caption2).foregroundStyle(.secondary) }
                }
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .accessibilityIdentifier("assistant.place-results")
    }

    private func appleMapsURL(_ place: Place) -> URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            .init(name: "daddr", value: "\(place.latitude),\(place.longitude)"),
            .init(name: "dirflg", value: "d")
        ]
        return components?.url
    }

    private func googleMapsURL(_ place: Place) -> URL? {
        var components = URLComponents(string: "https://www.google.com/maps/dir/")
        components?.queryItems = [
            .init(name: "api", value: "1"),
            .init(name: "destination", value: "\(place.latitude),\(place.longitude)")
        ]
        return components?.url
    }

    private func wazeURL(_ place: Place) -> URL? {
        var components = URLComponents(string: "https://waze.com/ul")
        components?.queryItems = [
            .init(name: "ll", value: "\(place.latitude),\(place.longitude)"),
            .init(name: "navigate", value: "yes")
        ]
        return components?.url
    }

    private func distanceText(_ meters: Double) -> String {
        meters < 1_000 ? "\(Int(meters.rounded())) м" : String(format: "%.1f км", meters / 1_000)
    }

    private func displayName(_ value: FuelConstraint) -> String {
        switch value {
        case .octane92: "А-92"; case .octane95: "А-95"; case .octane98: "А-98"
        case .octane100: "А-100"; case .diesel: "ДП"; case .lpg: "LPG"; case .cng: "CNG"
        }
    }
}
