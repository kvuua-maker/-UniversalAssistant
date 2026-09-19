import Foundation

enum CanonicalRoutingLane: String, Equatable, Sendable {
    case appleSystem
    case explicitProvider
    case officialBrand
    case localDiscovery
    case accommodation
    case restaurantReservation
    case jobs
    case events
    case delivery
    case informationalWeb
    case providerBoundary
    case specialized
    case clarification
}

struct CanonicalRoutingDecision: Equatable, Sendable {
    let lane: CanonicalRoutingLane
    let providerID: String?
    let reason: String
    let allowsMultipleResults: Bool
}

/// The single product-policy decision evaluated before the existing specialized
/// executors. It selects ownership; execution remains in the proven Apple,
/// provider, place, Jobs and web components.
struct CanonicalRoutingPolicy: Sendable {
    func decide(_ command: StructuredCommand) -> CanonicalRoutingDecision {
        if Self.appleSystemIntents.contains(command.intent) {
            return .init(lane: .appleSystem, providerID: nil,
                         reason: "apple_system_or_personal_intent", allowsMultipleResults: false)
        }

        if let provider = explicitProvider(in: command) {
            return .init(lane: .explicitProvider, providerID: provider.id,
                         reason: "explicit_named_provider", allowsMultipleResults: comparisonRequested(command))
        }

        if command.entities["provider_boundary"] == "external_current_service",
           let domain = command.entities["provider_domain"],
           !Self.zeroOwnerFunctionalDomains.contains(domain) {
            return .init(lane: .providerBoundary, providerID: nil,
                         reason: "typed_external_provider_boundary", allowsMultipleResults: false)
        }

        if command.entities["provider_domain"] == "jobs" {
            return .init(lane: .jobs, providerID: "jobs.workua",
                         reason: "jobs_internal_sources_unavailable_external_fallback", allowsMultipleResults: comparisonRequested(command))
        }

        if [.productSearch, .fashionDiscovery].contains(command.intent),
           let brand = explicitBrand(in: command) {
            return .init(lane: .officialBrand, providerID: BrandOfficialDestinationRegistry.id(for: brand),
                         reason: "explicit_brand_without_marketplace", allowsMultipleResults: comparisonRequested(command))
        }

        switch command.intent {
        case .placeSearch, .restaurantSearch:
            return .init(lane: .localDiscovery, providerID: "google.maps.url",
                         reason: "local_place_discovery", allowsMultipleResults: comparisonRequested(command))
        case .serviceSearch:
            if command.entities["provider_domain"] == "car_rental" {
                return .init(lane: .specialized, providerID: nil,
                             reason: "car_rental_requires_provider_or_specialized_boundary", allowsMultipleResults: comparisonRequested(command))
            }
            return .init(lane: .localDiscovery, providerID: "google.maps.url",
                         reason: "local_service_discovery", allowsMultipleResults: comparisonRequested(command))
        case .groceryBasket:
            if onlineRequested(command) {
                return .init(lane: .explicitProvider, providerID: "market.prom",
                             reason: "unnamed_online_grocery_ukraine_first", allowsMultipleResults: comparisonRequested(command))
            }
            return .init(lane: .localDiscovery, providerID: "google.maps.url",
                         reason: "unnamed_physical_retail_is_local_first", allowsMultipleResults: comparisonRequested(command))
        case .productSearch, .fashionDiscovery:
            if onlineRequested(command) {
                return .init(lane: .explicitProvider, providerID: "market.prom",
                             reason: "unnamed_online_product_ukraine_first", allowsMultipleResults: comparisonRequested(command))
            }
            return .init(lane: .localDiscovery, providerID: "google.maps.url",
                         reason: "unnamed_physical_product_is_local_first", allowsMultipleResults: comparisonRequested(command))
        case .hotelSearch:
            return .init(lane: .accommodation, providerID: "lodging.booking",
                         reason: "booking_primary_accommodation", allowsMultipleResults: comparisonRequested(command))
        case .reservation:
            return .init(lane: .restaurantReservation, providerID: nil,
                         reason: "restaurant_reservation_boundary", allowsMultipleResults: false)
        case .ticketSearch, .ticketPurchaseHandoff:
            let providerID: String
            if command.entities["provider_domain"] == "transport_tickets" {
                providerID = "transport.uz"
            } else if ticketFamily(command, roots: ["кіно", "cinema", "movie", "фільм", "сеанс"]) {
                providerID = "cinema.multiplex"
            } else if ticketFamily(command, roots: ["поїзд", "потяг", "заліз", "train", "rail"]) {
                providerID = "transport.uz"
            } else {
                providerID = "events.karabas"
            }
            return .init(lane: .events, providerID: providerID,
                         reason: "specialized_ticket_provider", allowsMultipleResults: comparisonRequested(command))
        case .parcelTrack:
            return .init(lane: .clarification, providerID: nil,
                         reason: "parcel_provider_required", allowsMultipleResults: false)
        case .webSearch:
            return .init(lane: .informationalWeb, providerID: nil,
                         reason: "explicit_informational_web_intent", allowsMultipleResults: false)
        default:
            return .init(lane: .specialized, providerID: nil,
                         reason: "existing_specialized_capability", allowsMultipleResults: comparisonRequested(command))
        }
    }

    private func explicitProvider(in command: StructuredCommand) -> OfficialPublicProviderHandoff? {
        if let id = command.entities["catalog_entity_id"],
           let provider = OfficialPublicProviderHandoffRegistry.records.first(where: { $0.id == id }) {
            return provider
        }
        let explicit = [command.entities["provider"], command.entities["retailer"]]
            .compactMap { $0 }.map(comparable)
        if let provider = OfficialPublicProviderHandoffRegistry.records.first(where: { provider in
            provider.aliases.union([provider.displayName, provider.id]).map(comparable)
                .contains(where: explicit.contains)
        }) { return provider }
        guard Self.providerBackedIntents.contains(command.intent) else { return nil }
        let text = " \(comparable(command.originalText)) "
        return OfficialPublicProviderHandoffRegistry.records.first { provider in
            provider.aliases.union([provider.displayName]).map(comparable)
                .contains { alias in !alias.isEmpty && text.contains(" \(alias) ") }
        }
    }

    private func explicitBrand(in command: StructuredCommand) -> String? {
        if let value = command.constraints.brand ?? command.entities["brand"],
           BrandOfficialDestinationRegistry.match(value) != nil { return value }
        return BrandOfficialDestinationRegistry.match(inText: command.originalText)?.displayName
    }

    private func comparable(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }

    private func comparisonRequested(_ command: StructuredCommand) -> Bool {
        if command.intent == .taxiCompare || command.entities["comparison_requested"] == "true" { return true }
        return ["порівн", "сравн", "compare", "варіант", "кілька", "несколько"]
            .contains(where: command.normalizedText.contains)
    }

    private func onlineRequested(_ command: StructuredCommand) -> Bool {
        command.entities["fulfillment"] == "delivery" ||
            ["онлайн", "online", "достав", "delivery"].contains(where: command.normalizedText.contains)
    }

    private func ticketFamily(_ command: StructuredCommand, roots: [String]) -> Bool {
        roots.contains(where: command.normalizedText.contains)
    }

    private static let appleSystemIntents: Set<CommandIntent> = [
        .open, .appAction, .contactLookup, .contactCall, .messageCompose,
        .calendarCreate, .calendarQuery, .calendarUpdate, .calendarDelete,
        .reminderCreate, .reminderQuery, .reminderComplete, .reminderDelete,
        .shoppingList, .noteCreate, .noteQuery, .photoSearch, .fileSearch,
        .cameraCapture, .translation, .musicRecognition, .mediaSearch,
        .podcastSearch, .deviceAction, .audioRecord, .settings
    ]

    private static let providerBackedIntents: Set<CommandIntent> = [
        .productSearch, .fashionDiscovery, .groceryBasket, .serviceSearch,
        .restaurantSearch, .reservation, .taxiSearch, .taxiCompare,
        .parcelTrack, .publicTransport, .ticketSearch, .ticketPurchaseHandoff,
        .hotelSearch, .travelPlan
    ]

    private static let zeroOwnerFunctionalDomains: Set<String> = [
        "product_catalog", "grocery_delivery", "jobs", "car_rental", "lodging",
        "tickets", "transport_tickets", "parcel_tracking", "restaurant_reservation"
    ]
}

struct BrandOfficialDestination: Equatable, Sendable {
    let id: String
    let displayName: String
    let aliases: Set<String>
    let route: OfficialPublicProviderRoute
    let evidence: URL
}

enum BrandOfficialDestinationRegistry {
    static let records: [BrandOfficialDestination] = [
        record("brand.baldinini", "Baldinini", "https://www.baldinini-shop.com/en/search", "q", "https://www.baldinini.com/"),
        record("brand.adidas", "Adidas", "https://www.adidas.ua/search", "q", "https://www.adidas.ua/"),
        record("brand.nike", "Nike", "https://www.nike.com/ua/w", "q", "https://www.nike.com/ua/"),
        record("brand.puma", "Puma", "https://ua.puma.com/uk/search", "q", "https://ua.puma.com/uk/"),
        record("brand.zara", "Zara", "https://www.zara.com/ua/uk/search", "searchTerm", "https://www.zara.com/ua/"),
        record("brand.mango", "Mango", "https://shop.mango.com/ua/uk/search", "q", "https://shop.mango.com/ua/"),
        record("brand.gucci", "Gucci", "https://www.gucci.com/ua/en_gb/st/search", "text", "https://www.gucci.com/ua/"),
        record("brand.pierre-cardin", "Pierre Cardin", "https://pierrecardin.com/en/search", "q", "https://pierrecardin.com/en/collections/all"),
        .init(id: "brand.prada", displayName: "Prada", aliases: ["prada"],
              route: .fixed(URL(string: "https://www.prada.com/ww/en.html")!),
              evidence: URL(string: "https://www.prada.com/")!)
    ]

    static func id(for value: String) -> String? { match(value)?.id }
    static func match(_ value: String) -> BrandOfficialDestination? {
        let key = comparable(value)
        return records.first { record in
            record.aliases.union([record.displayName]).map(comparable).contains(key)
        }
    }
    static func match(inText value: String) -> BrandOfficialDestination? {
        let text = " \(comparable(value)) "
        return records.first { record in
            record.aliases.union([record.displayName]).map(comparable)
                .contains { alias in !alias.isEmpty && text.contains(" \(alias) ") }
        }
    }

    private static func record(_ id: String, _ name: String, _ base: String, _ parameter: String, _ evidence: String) -> BrandOfficialDestination {
        .init(id: id, displayName: name, aliases: [name.lowercased()],
              route: .query(base: URL(string: base)!, parameter: parameter), evidence: URL(string: evidence)!)
    }
    private static func comparable(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }
}
