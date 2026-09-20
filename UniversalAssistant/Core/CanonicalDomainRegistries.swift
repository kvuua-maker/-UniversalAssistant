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
        record("groceries", "продукти", ["продукти", "їжа", "groceries", "food"])
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
            of: #"^\s*(?:купи(?:ти)?|придбай|замов|знайди|buy|find|order)\s+"#,
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
        let comparable = CanonicalMorphology.comparableText(command.originalText)
        let tokens = command.originalText.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .flatMap { CanonicalMorphology.forms(for: String($0)) }
        func hasTokenEvidence(_ stems: [String]) -> Bool {
            tokens.contains { token in stems.contains { token.hasPrefix($0) } }
        }
        let parcelEvidence = hasTokenEvidence(["посилк", "відправлен", "трек", "shipment", "parcel", "package", "tracking"])
        let purchaseEvidence = hasTokenEvidence(["куп", "придб", "замов", "buy", "purchase", "order"])
        let productCategory = CanonicalProductCategoryRegistry.match(in: command.originalText)

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
            constraints.category = productCategory.canonicalName
            constraints.hardConstraintKeys.insert("category")
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
        let jobEvidence = hasTokenEvidence(["робот", "ваканс", "працевлаш", "job", "vacanc"])
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
        return .init(id: command.id, originalText: command.originalText, normalizedText: command.normalizedText,
                     language: command.language, intent: intent, entities: entities, constraints: constraints,
                     risk: command.risk, needsClarification: command.needsClarification)
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
