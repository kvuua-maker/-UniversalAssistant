import Foundation

struct CanonicalPlaceCategoryDescriptor: Sendable {
    let category: PlaceCategory
    let aliases: Set<String>
    let searchTerm: String
}

/// Shared place vocabulary used by speech, semantic resolution and providers.
/// Provider adapters consume the canonical category and never maintain their
/// own Ukrainian intent dictionaries.
enum CanonicalPlaceCategoryRegistry {
    static let records: [CanonicalPlaceCategoryDescriptor] = [
        record(.cafe, "cafe", ["кафе", "кав'ярня", "кавярня", "coffee", "cafe"]),
        record(.restaurant, "restaurant", ["ресторан", "restaurant"]),
        record(.shop, "shop", ["магазин", "крамниця", "shop", "store"]),
        record(.supermarket, "supermarket", ["супермаркет", "supermarket", "grocery store"]),
        record(.mall, "shopping mall", ["торговий центр", "трц", "mall", "shopping centre"]),
        record(.pharmacy, "pharmacy", ["аптека", "аптеку", "pharmacy", "drugstore"]),
        record(.hospital, "hospital", ["лікарня", "больница", "hospital"]),
        record(.clinic, "clinic", ["клініка", "поліклініка", "clinic"]),
        record(.dentist, "dentist", ["стоматолог", "дантист", "dentist"]),
        record(.vet, "veterinary clinic", ["ветеринар", "ветклініка", "vet", "veterinary"]),
        record(.fuel, "fuel station", ["азс", "азк", "заправка", "заправку", "автозаправка", "бензоколонка", "fuel station", "gas station", "petrol station"]),
        record(.evCharging, "EV charging", ["електрозаправка", "зарядка для авто", "ev charging", "charging station"]),
        record(.parking, "parking", ["паркінг", "парковка", "parking"]),
        record(.bank, "bank", ["банк", "bank"]),
        record(.atm, "ATM", ["банкомат", "atm"]),
        record(.post, "post office", ["пошта", "поштове відділення", "post office"]),
        record(.hotel, "hotel", ["готель", "отель", "hotel"]),
        record(.carService, "car service", ["автосервіс", "сто", "car service", "mechanic"]),
        record(.tireService, "tire service", ["шиномонтаж", "tire service"]),
        record(.carWash, "car wash", ["автомийка", "мийка авто", "car wash"]),
        record(.tow, "tow service", ["евакуатор", "tow truck", "tow service"]),
        record(.beauty, "beauty salon", ["салон краси", "перукарня", "beauty salon", "hairdresser"]),
        record(.repair, "repair service", ["ремонт", "майстерня", "repair service"]),
        record(.government, "government service", ["цнап", "державна установа", "government service"]),
        record(.police, "police", ["поліція", "police"])
    ]

    static var speechVocabulary: [String] {
        Array(records.flatMap { $0.aliases }.sorted().prefix(120))
    }

    static func match(in text: String) -> CanonicalPlaceCategoryDescriptor? {
        let normalized = comparable(text)
        let padded = " \(normalized) "
        let tokenForms = Set(text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .flatMap { CanonicalMorphology.forms(for: String($0)) })
        return records.first { record in
            record.aliases.contains { alias in
                let candidate = comparable(alias)
                return normalized == candidate || padded.contains(" \(candidate) ") ||
                    normalized.hasPrefix(candidate + " ") || normalized.hasSuffix(" " + candidate) ||
                    !tokenForms.isDisjoint(with: CanonicalMorphology.forms(for: alias))
            }
        }
    }

    static func record(for category: PlaceCategory) -> CanonicalPlaceCategoryDescriptor? {
        records.first { $0.category == category }
    }

    private static func record(_ category: PlaceCategory, _ searchTerm: String, _ aliases: Set<String>) -> CanonicalPlaceCategoryDescriptor {
        .init(category: category, aliases: aliases, searchTerm: searchTerm)
    }

    private static func comparable(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }
}

enum FuelConstraint: String, Codable, CaseIterable, Sendable {
    case octane92, octane95, octane98, octane100, diesel, lpg, cng
}

enum CanonicalFuelConstraintResolver {
    static func resolve(in text: String, category: PlaceCategory?) -> FuelConstraint? {
        guard category == .fuel else { return nil }
        let normalized = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
        let compact = normalized.replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
        let tokens = Set(compact.split(separator: " ").map(String.init))
        let tokenForms = Set(compact.split(separator: " ").flatMap { CanonicalMorphology.forms(for: String($0)) })
        if tokens.contains("lpg") || tokenForms.contains("автогаз") || tokenForms.contains("газ") { return .lpg }
        if tokens.contains("cng") || normalized.contains("метан") { return .cng }
        if tokens.contains("дп") || normalized.contains("дизел") || tokens.contains("diesel") { return .diesel }
        for (number, value) in [("100", FuelConstraint.octane100), ("98", .octane98), ("95", .octane95), ("92", .octane92)] {
            if tokens.contains(number) || normalized.range(of: #"(?:а|sp)[-\s]?"# + number, options: .regularExpression) != nil {
                return value
            }
        }
        return nil
    }
}

struct CanonicalProductCategoryDescriptor: Sendable {
    let id: String
    let canonicalName: String
    let aliases: Set<String>
}

enum CanonicalProductCategoryRegistry {
    static let records: [CanonicalProductCategoryDescriptor] = [
        record("sneakers", "кросівки", ["кросівки", "кросовки", "sneakers", "trainers"]),
        record("slippers", "домашні тапочки", ["тапочки", "капці", "шльопанці", "slippers", "house shoes"]),
        record("boots", "черевики", ["черевики", "ботинки", "чоботи", "boots"]),
        record("shoes", "взуття", ["взуття", "обувь", "shoes"]),
        record("shirt", "сорочка", ["сорочка", "рубашка", "shirt"]),
        record("tshirt", "футболка", ["футболка", "t shirt", "t-shirt"]),
        record("trousers", "штани", ["штани", "брюки", "trousers", "pants"]),
        record("jeans", "джинси", ["джинси", "джинсы", "jeans"]),
        record("jacket", "куртка", ["куртка", "jacket"]),
        record("coat", "пальто", ["пальто", "coat"]),
        record("dress", "сукня", ["сукня", "платье", "dress"]),
        record("bag", "сумка", ["сумка", "bag"]),
        record("backpack", "рюкзак", ["рюкзак", "backpack"]),
        record("watch", "годинник", ["годинник", "часы", "watch"]),
        record("phone", "телефон", ["смартфон", "телефон", "phone", "smartphone"]),
        record("laptop", "ноутбук", ["ноутбук", "laptop"]),
        record("furniture", "меблі", ["меблі", "мебель", "furniture"]),
        record("groceries", "продукти", ["продукти", "їжа", "groceries", "food"]),
        record("cheese", "сир", ["сир", "cheese"]),
        record("oil", "олія", ["олія", "масло", "oil", "olive oil", "оливкова олія"]),
        record("milk", "молоко", ["молоко", "milk"]),
        record("yogurt", "йогурт", ["йогурт", "yogurt"]),
        record("beverage", "напої", ["напій", "напої", "beverage", "drink"]),
        record("pasta", "макарони", ["макарони", "паста", "pasta"]),
        record("cereal", "крупи", ["крупа", "крупи", "cereal", "grain"]),
        record("canned", "консерви", ["консерви", "canned food"]),
        record("snack", "снеки", ["снек", "снеки", "snack", "chips"])
    ]

    static func match(in text: String) -> CanonicalProductCategoryDescriptor? {
        let words = Set(text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { CanonicalMorphology.comparableText(String($0)) })
        return records.first { record in
            record.aliases.contains { alias in
                let forms = CanonicalMorphology.forms(for: alias)
                return !words.isDisjoint(with: forms)
            }
        }
    }

    static var speechVocabulary: [String] { records.flatMap { $0.aliases }.sorted() }

    private static func record(_ id: String, _ canonical: String, _ aliases: Set<String>) -> CanonicalProductCategoryDescriptor {
        .init(id: id, canonicalName: canonical, aliases: aliases)
    }
}

enum CanonicalOpenWorldBrandExtractor {
    static func explicitBrandPhrase(in original: String, knownCategory: CanonicalProductCategoryDescriptor?) -> String? {
        guard ["куп", "придб", "замов", "buy", "find", "знайд"].contains(where: CanonicalMorphology.comparableText(original).contains) else { return nil }
        var value = original.replacingOccurrences(
            of: #"^\s*(?:(?:де|where)\s+(?:поруч|nearby)\s+)?(?:купи(?:ти)?|придбай|замов|знайди|buy|find|order)\s+"#,
            with: "", options: [.regularExpression, .caseInsensitive]
        )
        if let category = knownCategory {
            for alias in category.aliases { value = value.replacingOccurrences(of: alias, with: "", options: [.caseInsensitive, .diacriticInsensitive]) }
        }
        value = value.replacingOccurrences(of: #"\b(?:розмір(?:у)?|size)\s*[A-Z0-9.-]+\b"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !value.isEmpty, value.rangeOfCharacter(from: .letters) != nil else { return nil }
        let tokens = value.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "&" })
        guard tokens.count <= 6 else { return nil }
        return value
    }
}

enum CanonicalDomainIntegrityPolicy {
    static func apply(to command: StructuredCommand) -> StructuredCommand {
        var intent = command.intent
        var entities = command.entities
        var constraints = command.constraints
        var needsClarification = command.needsClarification
        let comparable = CanonicalMorphology.comparableText(command.originalText)
        let tokens = command.originalText.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .flatMap { CanonicalMorphology.forms(for: String($0)) }
        func hasTokenEvidence(_ stems: [String]) -> Bool {
            tokens.contains { token in stems.contains { token.hasPrefix($0) } }
        }
        let parcelEvidence = hasTokenEvidence(["посилк", "відправлен", "трек", "shipment", "parcel", "package", "tracking"])
        let purchaseEvidence = hasTokenEvidence(["куп", "придб", "замов", "buy", "purchase", "order"])
        let productCategory = CanonicalProductCategoryRegistry.match(in: command.originalText)
        let jobEvidence = hasTokenEvidence(["робот", "ваканс", "працевлаш", "job", "vacanc"])
        let englishTokens = Set(command.originalText.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        let bookEvidence = hasTokenEvidence(["книг", "книж", "читат", "автор"]) ||
            !englishTokens.isDisjoint(with: ["book", "novel", "read"])
        let safetyEvidence = hasTokenEvidence(["тривог", "небезпек", "alert", "alarm"]) &&
            hasTokenEvidence(["повітр", "неб", "air", "sky", "civil"])
        let automotive = CanonicalAutomotiveEntityExtractor.domainEvidence(in: command.originalText)
        let providerRoleMarker = hasTokenEvidence([
            "маркетплейс", "магазин", "сайт", "через", "marketplace", "store", "site", "via"
        ]) || command.originalText.split(whereSeparator: { !$0.isLetter }).contains {
            ["на", "у", "в", "on", "at", "from"].contains(CanonicalMorphology.comparableText(String($0)))
        }
        let exactProviders = OfficialPublicProviderHandoffRegistry.records.filter {
            isExact($0, in: command.originalText)
        }
        let isPersonalOrCommunication = [.contactLookup, .contactCall, .messageCompose].contains(intent)
        if exactProviders.count == 1, let provider = exactProviders.first, !isPersonalOrCommunication,
           providerRoleMarker || [.productSearch, .fashionDiscovery, .groceryBasket, .hotelSearch,
                                  .serviceSearch, .ticketSearch, .ticketPurchaseHandoff,
                                  .parcelTrack].contains(intent) || jobEvidence || parcelEvidence {
            entities["catalog_entity_id"] = provider.id
            if provider.domain == .grocery { entities["retailer"] = provider.displayName }
            else { entities["provider"] = provider.displayName }
            switch provider.domain {
            case .marketplace:
                intent = .productSearch; entities["provider_domain"] = "product_catalog"
            case .grocery:
                intent = .groceryBasket; entities["provider_domain"] = "grocery_delivery"
            case .lodging:
                intent = .hotelSearch; entities["provider_domain"] = "lodging"
            case .carRental:
                intent = .serviceSearch; entities["provider_domain"] = "car_rental"
            case .events, .cinema:
                intent = .ticketSearch; entities["provider_domain"] = "tickets"
            case .transport:
                intent = .ticketSearch; entities["provider_domain"] = "transport_tickets"
            case .jobs:
                intent = .productSearch; entities["provider_domain"] = "jobs"
            case .parcel:
                intent = .parcelTrack; entities["provider_domain"] = "parcel_tracking"
            }
            needsClarification = false
        }

        // Mixed-catalog fuzzy output is not authoritative. A provider may
        // survive only when its exact alias is present in the current text and
        // its domain is compatible with the command's structural evidence.
        if let catalogID = entities["catalog_entity_id"],
           let provider = OfficialPublicProviderHandoffRegistry.records.first(where: { $0.id == catalogID }),
           !CanonicalDomainIntegrityPolicy.isExact(provider, in: command.originalText),
           !isScopedProviderRecovery(provider, entities: entities, intent: intent, hasRoleMarker: providerRoleMarker) {
            entities.removeValue(forKey: "catalog_entity_id")
            entities.removeValue(forKey: "provider")
            entities.removeValue(forKey: "retailer")
            if !jobEvidence && !parcelEvidence { entities.removeValue(forKey: "provider_domain") }
        }

        if safetyEvidence {
            intent = .webSearch
            entities = [
                "provider_domain": "current_safety",
                "current_safety": "air_alert",
                "protected_system_command": "true",
                "direct_url": "https://map.ukrainealarm.com/",
                "query": command.originalText
            ]
            constraints = .init()
        } else if bookEvidence && !jobEvidence {
            intent = .webSearch
            entities.removeValue(forKey: "catalog_entity_id")
            entities.removeValue(forKey: "provider")
            entities.removeValue(forKey: "retailer")
            entities["provider_domain"] = "books"
            entities["query"] = command.originalText
            entities["book_query"] = CanonicalBookQueryExtractor.title(in: command.originalText)
        } else if automotive.ownsVehicleDomain, !resolvedServiceDomain(entities["provider_domain"]) {
            // Automotive domain ownership follows the meaning of the request.
            // A vehicle the user wants to acquire must never degrade into a
            // generic product catalogue, so an unknown marque reaches the
            // automotive dealer surface with the brand carried as data.
            intent = .placeSearch
            entities.removeValue(forKey: "catalog_entity_id")
            entities.removeValue(forKey: "provider")
            entities.removeValue(forKey: "retailer")
            entities["provider_domain"] = "automotive_dealer"
            entities["place_category"] = PlaceCategory.shop.rawValue
            if let brand = automotive.brandAndModel {
                entities["automotive_brand"] = brand
                entities["brand"] = brand
                entities["query"] = "official \(brand) dealer showroom"
                constraints.brand = brand
                constraints.hardConstraintKeys.insert("brand")
            } else {
                entities["query"] = "car dealer showroom"
                constraints.brand = nil
                constraints.hardConstraintKeys.remove("brand")
            }
            entities["near_current_location"] = "true"
            needsClarification = false
        }

        if intent == .parcelTrack && !parcelEvidence && (purchaseEvidence || productCategory != nil) {
            intent = .productSearch
            entities.removeValue(forKey: "provider")
            entities.removeValue(forKey: "retailer")
            entities.removeValue(forKey: "catalog_entity_id")
            entities["provider_domain"] = "product_catalog"
        }
        if [.productSearch, .fashionDiscovery].contains(intent), !parcelEvidence,
           entities["provider_domain"] == "parcel_tracking" {
            entities["provider_domain"] = "product_catalog"
            entities.removeValue(forKey: "provider")
            entities.removeValue(forKey: "catalog_entity_id")
        }
        if purchaseEvidence, let productCategory {
            intent = .productSearch
            entities["product_category"] = productCategory.id
            entities["product"] = productCategory.canonicalName
            entities["query"] = CanonicalProductQueryBuilder.query(
                for: .init(
                    id: command.id, originalText: command.originalText,
                    normalizedText: command.normalizedText, language: command.language,
                    intent: .productSearch, entities: ["query": command.originalText],
                    constraints: command.constraints, risk: command.risk,
                    needsClarification: false
                ),
                selectedProviderOrBrand: entities["retailer"] ?? entities["provider"]
            )
            constraints.category = productCategory.canonicalName
            constraints.hardConstraintKeys.insert("category")
        }
        let proximityEvidence = ["поруч", "біля мене", "nearby", "near me"].contains(where: comparable.contains)
        if purchaseEvidence, proximityEvidence, let productCategory {
            intent = .placeSearch
            entities.removeValue(forKey: "provider_domain")
            entities["place_category"] = PlaceCategory.shop.rawValue
            entities["query"] = productCategory.canonicalName
            entities["near_current_location"] = "true"
            entities.removeValue(forKey: "brand")
            entities.removeValue(forKey: "open_world_brand")
            constraints.brand = nil
            constraints.hardConstraintKeys.remove("brand")
        }
        if [.productSearch, .fashionDiscovery].contains(intent), constraints.brand == nil,
           let brand = CanonicalOpenWorldBrandExtractor.explicitBrandPhrase(in: command.originalText, knownCategory: productCategory) {
            constraints.brand = brand
            constraints.hardConstraintKeys.insert("brand")
            entities["brand"] = brand
            entities["open_world_brand"] = "true"
        }
        if let placeCategory = CanonicalPlaceCategoryRegistry.match(in: command.originalText),
           [.unknown, .webSearch, .show, .productSearch, .placeSearch, .serviceSearch, .routeAwareSearch].contains(intent),
           !purchaseEvidence {
            if intent != .routeAwareSearch { intent = .placeSearch }
            entities["place_category"] = placeCategory.category.rawValue
            entities["query"] = placeCategory.searchTerm
            if ["поруч", "біля мене", "nearby", "near me"].contains(where: comparable.contains) {
                entities["near_current_location"] = "true"
            }
            if let fuel = CanonicalFuelConstraintResolver.resolve(in: command.originalText, category: placeCategory.category) {
                entities["fuel_constraint"] = fuel.rawValue
            }
        }
        // If a booking request names no establishment and is still missing
        // booking roles, selecting the physical restaurant is the useful next
        // action. A fully specified availability request remains a reservation
        // so an injected live reservation provider can execute it directly.
        if intent == .reservation, needsClarification,
           isGenericRestaurantSubject(entities["restaurant_query"]) {
            intent = .placeSearch
            entities["place_category"] = PlaceCategory.restaurant.rawValue
            entities["query"] = CanonicalPlaceCategoryRegistry.record(for: .restaurant)?.searchTerm ?? "restaurant"
            entities["near_current_location"] = entities["location"] == nil ? "true" : entities["near_current_location"]
            entities.removeValue(forKey: "clarification_options")
            entities.removeValue(forKey: "clarification_role")
            needsClarification = false
        }
        if jobEvidence {
            intent = .productSearch
            entities["provider_domain"] = "jobs"
            entities["job_role"] = CanonicalJobsRoleExtractor.role(in: command.originalText)
            if let locality = CanonicalJobsRoleExtractor.locality(in: command.originalText) {
                entities["location"] = locality
                entities["explicit_location"] = "true"
            }
            if let salary = CanonicalJobsRoleExtractor.minimumSalary(in: command.originalText) {
                entities["salary_minimum"] = salary
                entities["currency"] = "UAH"
            }
            if entities["catalog_entity_id"]?.hasPrefix("jobs.") != true {
                entities.removeValue(forKey: "provider")
                entities.removeValue(forKey: "catalog_entity_id")
            }
        }
        if !jobEvidence, entities["provider_domain"] == "jobs" {
            entities.removeValue(forKey: "provider_domain")
            entities.removeValue(forKey: "provider")
            if entities["catalog_entity_id"]?.hasPrefix("jobs.") == true {
                entities.removeValue(forKey: "catalog_entity_id")
            }
        }
        if !parcelEvidence, entities["provider_domain"] == "parcel_tracking" {
            entities.removeValue(forKey: "provider_domain")
            entities.removeValue(forKey: "provider")
            if entities["catalog_entity_id"]?.hasPrefix("parcel.") == true {
                entities.removeValue(forKey: "catalog_entity_id")
            }
        }
        return .init(id: command.id, originalText: command.originalText, normalizedText: command.normalizedText,
                     language: command.language, intent: intent, entities: entities, constraints: constraints,
                     risk: command.risk, needsClarification: needsClarification)
    }

    /// Domains that already own this request through a verified service path.
    /// Automotive analysis must never displace them.
    private static func resolvedServiceDomain(_ domain: String?) -> Bool {
        domain == "car_rental" || domain == "vehicle_service" || domain == "current_safety"
    }

    private static func isGenericRestaurantSubject(_ value: String?) -> Bool {
        guard let value else { return true }
        let tokens = CanonicalMorphology.comparableText(value)
            .split(whereSeparator: { !$0.isLetter }).map(String.init)
        guard !tokens.isEmpty else { return true }
        let controlStems = ["ресторан", "заклад", "столик", "restaurant", "table"]
        return tokens.allSatisfy { token in controlStems.contains(where: token.hasPrefix) }
    }

    private static func isExact(_ provider: OfficialPublicProviderHandoff, in text: String) -> Bool {
        let comparable = " " + tokenComparable(text) + " "
        return provider.aliases.union([provider.displayName]).contains { alias in
            let value = tokenComparable(alias)
            return !value.isEmpty && comparable.contains(" \(value) ")
        }
    }

    private static func isScopedProviderRecovery(
        _ provider: OfficialPublicProviderHandoff,
        entities: [String: String],
        intent: CommandIntent,
        hasRoleMarker: Bool
    ) -> Bool {
        let domain = entities["provider_domain"]
        let compatible: Bool = switch provider.domain {
        case .marketplace: [.productSearch, .fashionDiscovery].contains(intent) && domain == "product_catalog"
        case .grocery: intent == .groceryBasket && domain == "grocery_delivery"
        case .lodging: intent == .hotelSearch && domain == "lodging"
        case .carRental: intent == .serviceSearch && domain == "car_rental"
        case .events, .cinema: [.ticketSearch, .ticketPurchaseHandoff].contains(intent) && domain == "tickets"
        case .transport: [.ticketSearch, .ticketPurchaseHandoff].contains(intent) && domain == "transport_tickets"
        case .jobs: intent == .productSearch && domain == "jobs"
        case .parcel: intent == .parcelTrack && domain == "parcel_tracking"
        }
        guard compatible else { return false }
        let mechanism = entities["catalog_match_mechanism"]
        if mechanism == "morphology" { return true }
        let confidence = Double(entities["catalog_match_confidence"] ?? "") ?? 0
        return hasRoleMarker && mechanism == "phonetic" && confidence >= 0.72
    }

    private static func tokenComparable(_ value: String) -> String {
        value.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { CanonicalMorphology.comparableText(String($0)) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

enum CanonicalAutomotiveEntityExtractor {
    /// Typed outcome of automotive domain analysis. Brand and model are data on
    /// this value, never the reason the domain was selected.
    struct DomainEvidence: Sendable {
        /// The request is about acquiring a vehicle, so the automotive domain
        /// owns it even when no marque is recognized.
        let ownsVehicleDomain: Bool
        let brandAndModel: String?
    }

    /// Vehicle object vocabulary. These describe the kind of object the user is
    /// asking about, so an unknown manufacturer still owns this domain.
    /// Cyrillic roots match on a productive prefix; Latin roots match only as a
    /// whole evidence form so unrelated words sharing letters cannot match.
    private static let vehicleObjectRoots = ["авто", "автомоб", "машин"]
    private static let vehicleBodyRoots = [
        "седан", "хетчбек", "хэтчбек", "універсал", "кросовер",
        "пікап", "пикап", "фургон", "мікроавтобус", "спорткар", "кабріолет"
    ]
    private static let vehiclePowertrainRoots = ["електромобіл", "електроавто", "гібрид"]
    private static let latinVehicleForms: Set<String> = [
        "car", "cars", "vehicle", "vehicles", "suv", "suvs", "sedan", "sedans",
        "hatchback", "crossover", "pickup", "minivan", "coupe", "cabriolet", "hybrid"
    ]
    /// Series/model language lets an ownership request own the automotive domain
    /// when no vehicle object noun was spoken.
    private static let vehicleSpecificationRoots = [
        "сері", "модифікац", "комплектац", "двигун", "привід", "пробіг", "vin"
    ]
    /// Public transport is a separate domain and must never be captured here.
    private static let publicTransportRoots = [
        "автобус", "автобуси", "трамва", "потяг", "поїзд", "метро", "маршрутк", "тролейбус"
    ]
    /// Parts, consumables and servicing stay in commerce/service ownership. They
    /// mention a vehicle but do not acquire one.
    private static let vehiclePartsRoots = [
        "запчаст", "масл", "масло", "олив", "олі", "шини", "шина", "резин", "колодк",
        "батаре", "свіч", "фільтр", "заправ", "митт", "мийк", "шиномонтаж", "автосервіс"
    ]
    private static let physicalDealerRoots = [
        "дилер", "шоурум", "автосалон", "dealer", "dealership", "showroom", "testdrive"
    ]
    /// Ownership excludes bare "order": that form stays ambiguous between a
    /// ride, a rental and a purchase, exactly as the verified service ambiguity
    /// already resolves it.
    private static let ownershipRoots = ["куп", "придб"]
    private static let rentalRoots = ["оренд", "прокат"]
    private static let rideRoots = ["таксі", "такси"]
    /// Latin evidence is matched as whole forms for the same reason Cyrillic
    /// prefixes are safe here: "card" must not satisfy "car".
    private static let latinServiceForms: Set<String> = ["rent", "rental", "hire", "ride", "taxi"]

    /// Words that carry no brand information and must be stripped before an
    /// open-world marque is read as residual text. Vehicle object and body
    /// vocabulary belongs here too: it names the kind of vehicle, never the
    /// manufacturer.
    private static let residualNoiseRoots = [
        "куп", "придб", "замов", "закаж", "знайд", "покаж", "підбер", "хочу",
        "авто", "автомоб", "машин", "car", "vehicle", "офіційн", "официальн",
        "official", "дилер", "шоурум", "dealer", "тестдрайв", "testdrive",
        "новий", "новый", "new", "сері", "модифікац", "комплектац",
        "привід", "двигун", "пробіг", "vin", "клас", "рік", "year",
        "седан", "хетчбек", "хэтчбек", "універсал", "кросовер",
        "пікап", "пикап", "фургон", "мікроавтобус", "спорткар", "кабріолет",
        "електромобіл", "електроавто", "гібрид", "suv", "sedan", "hatchback",
        "crossover", "pickup", "minivan", "coupe", "cabriolet", "hybrid",
        "для", "про", "щоб", "тако", "замало", "бистро", "бажано",
        "салон", "де", "та", "там", "тут", "туди"
    ]

    static func domainEvidence(in text: String) -> DomainEvidence {
        let forms = Set(text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .flatMap { CanonicalMorphology.forms(for: String($0)) })
        func has(_ roots: [String]) -> Bool {
            forms.contains { value in roots.contains { value.hasPrefix($0) } }
        }
        guard !has(publicTransportRoots), !has(vehiclePartsRoots),
              forms.isDisjoint(with: latinServiceForms) else {
            return .init(ownsVehicleDomain: false, brandAndModel: nil)
        }
        // A resolved ride/rental service already owns this request. Capturing it
        // here would replace a verified car-rental capability with a dealer query.
        guard !has(rideRoots), !has(rentalRoots) else {
            return .init(ownsVehicleDomain: false, brandAndModel: nil)
        }
        let vehicleObject = has(vehicleObjectRoots) || has(vehicleBodyRoots) ||
            has(vehiclePowertrainRoots) || !forms.isDisjoint(with: latinVehicleForms)
        let specification = has(vehicleSpecificationRoots)
        let ownership = has(ownershipRoots) || has(physicalDealerRoots)
        // A marque verified by the existing automotive regexes is trusted
        // evidence on its own, which preserves the already verified
        // marque-plus-official path. A residual open-world marque is *data* and
        // never decides ownership on its own: without vehicle semantics the
        // request stays unresolved rather than being guessed into this domain.
        let verifiedMarque = trustedMarque(in: text)
        guard ownership, vehicleObject || specification || verifiedMarque != nil else {
            return .init(ownsVehicleDomain: false, brandAndModel: nil)
        }
        return .init(ownsVehicleDomain: true, brandAndModel: brandAndModel(in: text))
    }

    /// Marques whose automotive identity is already verified in the production
    /// corridor. This is pre-existing verified scope, not a general brand list.
    private static func trustedMarque(in text: String) -> String? {
        let patterns = [
            #"\b(BMW(?:\s+[A-Z0-9][A-Z0-9 .-]{0,20})?)\b"#,
            #"\b(Mercedes(?:-Benz)?(?:\s+[A-Z0-9][A-Z0-9 .-]{0,20})?)\b"#,
            #"\b(Rolls(?:-|\s)Royce(?:\s+[A-Z0-9][A-Z0-9 .-]{0,20})?)\b"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { continue }
            return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        }
        return nil
    }

    /// Marque data for an already owned automotive request: the verified marque
    /// when one is present, otherwise whatever the user actually said once the
    /// control, object and specification words are removed.
    static func brandAndModel(in text: String) -> String? {
        trustedMarque(in: text) ?? residualBrandAndModel(in: text)
    }

    /// Open-world marque reading: whatever the user actually said after the
    /// control, object and specification words are removed is the marque data.
    /// No manufacturer list participates in this decision.
    private static func residualBrandAndModel(in text: String) -> String? {
        var residuals: [String] = []
        for rawToken in text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            let token = String(rawToken)
            // A one/two-character token is a preposition or an article, never a
            // marque. Rejecting it here keeps function words out of the query.
            guard token.count >= 3 else { continue }
            let forms = CanonicalMorphology.forms(for: token)
            if forms.contains(where: { value in residualNoiseRoots.contains { value.hasPrefix($0) } }) {
                continue
            }
            residuals.append(token)
        }
        guard let first = residuals.first, first.rangeOfCharacter(from: .letters) != nil else { return nil }
        // A marque plus an adjacent model token is usable data; more than that
        // is unverified residual text and must not become a query.
        guard residuals.count <= 2 else { return nil }
        let value = residuals.joined(separator: " ")
        return value.rangeOfCharacter(from: .letters) == nil ? nil : value
    }
}

enum CanonicalBookQueryExtractor {
    static func title(in text: String) -> String {
        text.replacingOccurrences(
            of: #"^\s*(?:знайд\p{L}*|відкрий|покажи|де\s+читати|читати|find|read)\s+(?:книг\p{L}*\s+)?"#,
            with: "", options: [.regularExpression, .caseInsensitive]
        ).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
}

enum CanonicalJobsRoleExtractor {
    static func role(in text: String) -> String {
        var value = text.replacingOccurrences(
            of: #"^\s*(?:знайд\p{L}*|покаж\p{L}*|find|show)\s+(?:мені\s+)?(?:робот\p{L}*|ваканс\p{L}*)\s*"#,
            with: "", options: [.regularExpression, .caseInsensitive]
        )
        value = value.replacingOccurrences(of: #"\s+(?:у|в|біля|near|in)\s+[\p{L}'’ -]+?(?=\s+(?:від|до|salary|pay)|$)"#, with: "", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: #"\s+(?:від|salary|pay)\s*[0-9\s]+(?:грн|uah)?\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        return value.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).nilIfEmpty ?? "вакансії"
    }

    static func locality(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"\b(?:у|в|in)\s+([\p{L}'’ -]{2,60}?)(?=\s+(?:від|до|salary|pay)|$)"#, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return CanonicalLocalityNormalizer.normalize(String(text[range]))
    }

    static func minimumSalary(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"\b(?:від|salary|pay)\s*([0-9][0-9\s]{2,})"#, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        let digits = text[range].filter(\.isNumber)
        return digits.isEmpty ? nil : String(digits)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
