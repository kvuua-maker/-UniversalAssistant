import Foundation

/// Free Google Maps URL handoff. This uses no Google API, key, SDK or billing
/// project and is the owner-selected primary presentation for nearby discovery.
struct GoogleMapsSearchHandoff: Sendable {
    func destination(for command: StructuredCommand) -> URL? {
        var terms: [String] = []
        if let automotive = command.entities["automotive_brand"] {
            terms += ["official", automotive, "dealer showroom"]
        } else if let raw = command.entities["query"], !raw.isEmpty {
            terms.append(raw)
        } else if let raw = command.entities["restaurant_query"], !raw.isEmpty {
            terms.append(raw)
        } else if let raw = command.entities["serviceCategory"], !raw.isEmpty {
            terms.append(raw)
        } else if let raw = command.entities["place_category"],
                  let category = PlaceCategory(rawValue: raw),
                  let record = CanonicalPlaceCategoryRegistry.record(for: category) {
            terms.append(record.searchTerm)
        } else {
            terms.append(command.originalText)
        }
        if let raw = command.entities["fuel_constraint"], let fuel = FuelConstraint(rawValue: raw) {
            let fuelTerm: String = switch fuel {
            case .octane92: "A-92"
            case .octane95: "A-95"
            case .octane98: "A-98 98"
            case .octane100: "A-100"
            case .diesel: "diesel ДП"
            case .lpg: "LPG автогаз"
            case .cng: "CNG метан"
            }
            terms.append(fuelTerm)
        }
        if let locality = command.entities["location"] ?? command.entities["destination"], !locality.isEmpty {
            terms.append(CanonicalLocalityNormalizer.normalize(locality))
        } else if command.entities["near_current_location"] == "true" {
            terms.append("nearby")
        }
        let query = terms.joined(separator: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !query.isEmpty else { return nil }
        var components = URLComponents(string: "https://www.google.com/maps/search/")
        components?.queryItems = [
            .init(name: "api", value: "1"),
            .init(name: "query", value: query)
        ]
        return components?.url
    }

    func shouldOpenImmediately(_ command: StructuredCommand) -> Bool {
        if command.entities["compound_dependency_required"] == "true" { return false }
        if command.entities["provider_domain"] == "automotive_dealer" { return true }
        switch command.intent {
        case .placeSearch, .restaurantSearch:
            return command.entities["near_current_location"] == "true" ||
                command.entities["location"] != nil || command.entities["place_category"] != nil ||
                command.entities["query"] != nil
        case .serviceSearch:
            // Named/dated service workflows (for example a car-rental
            // provider) remain in their structured engine. Only physical
            // nearby/category discovery uses the immediate Maps surface.
            return command.entities["near_current_location"] == "true" ||
                command.entities["place_category"] != nil
        default:
            return false
        }
    }
}
