import Foundation

enum CommandLanguage: String, Codable, Sendable { case uk, ru, en, de, fr, automatic }
enum CommandIntent: String, Codable, CaseIterable, Sendable {
    case placeSearch, productSearch, fashionDiscovery, groceryBasket, serviceSearch, restaurantSearch, reservation
    case taxiSearch, taxiCompare, navigation, routeSearch, routeAwareSearch
    case calendarCreate, calendarQuery, calendarUpdate, calendarDelete, reminderCreate, reminderQuery
    case noteCreate, noteQuery, shoppingList, contactLookup, contactCall, messageCompose, weather
    case publicTransport, transportRoute, ticketSearch, ticketPurchaseHandoff, hotelSearch, travelPlan
    case emergency, webSearch, deviceAction, appAction, audioRecord, show, open, cancel, undo
    case multiStep, settings, help, contextualSelection, unknown
}
enum ActionRisk: String, Codable, Sendable { case informational, reversible, consequential, emergency }

struct CommandConstraints: Equatable, Codable, Sendable {
    var maximumPrice: Decimal?
    var currency: String?
    var size: String?
    var color: String?
    var brand: String?
    var category: String?
    var season: String?
    var ordinal: Int?
    var hardConstraintKeys: Set<String> = []
}

struct StructuredCommand: Equatable, Codable, Sendable {
    let id: UUID
    let originalText: String
    let normalizedText: String
    let language: CommandLanguage
    let intent: CommandIntent
    let entities: [String: String]
    let constraints: CommandConstraints
    let risk: ActionRisk
    let needsClarification: Bool

    init(id: UUID = UUID(), originalText: String, normalizedText: String, language: CommandLanguage, intent: CommandIntent, entities: [String: String] = [:], constraints: CommandConstraints = .init(), risk: ActionRisk = .informational, needsClarification: Bool = false) {
        self.id = id; self.originalText = originalText; self.normalizedText = normalizedText
        self.language = language; self.intent = intent; self.entities = entities
        self.constraints = constraints; self.risk = risk; self.needsClarification = needsClarification
    }
}

protocol CommandParsing: Sendable { func parse(_ text: String) -> StructuredCommand }

struct LocalCommandEngine: CommandParsing {
    private static let intentPatterns: [(CommandIntent, [String])] = [
        (.undo, ["відміни останнє", "отмени последнее", "undo last", "rückgängig", "annule la dernière"]),
        (.emergency, ["112", "швидка", "скорая", "ambulance", "polizei", "police", "пожежа", "пожар"]),
        (.calendarCreate, ["запиши", "додай зустріч", "создай встреч", "add event", "termin erstellen", "ajoute un rendez-vous"]),
        (.reminderCreate, ["нагадай", "напомни", "remind", "erinnere", "rappelle"]),
        (.contactCall, ["подзвони", "позвони", "call ", "ruf ", "appelle"]),
        (.messageCompose, ["напиши ", "отправь сообщение", "message ", "schreib ", "écris "]),
        (.navigation, ["веди ", "маршрут до", "navigate", "route to", "navigiere", "itinéraire"]),
        (.weather, ["погод", "weather", "wetter", "météo"]),
        (.audioRecord, ["диктофон", "запиши аудіо", "voice recorder", "sprachmemo", "enregistre audio"]),
        (.ticketSearch, ["квиток", "квитки", "билет", "ticket", "fahrkarte", "billet"]),
        (.hotelSearch, ["готель", "отель", "hotel", "hôtel", "квартиру"]),
        (.serviceSearch, ["евакуатор", "tow truck", "abschlepp", "dépanneuse", "сантехнік", "сантехник", "plumber", "klempner", "plombier", "слюсар", "locksmith", "schlüsseldienst", "serrurier", "електрик", "электрик", "electrician", "elektriker", "électricien", "клінінг", "cleaning", "reinigung", "nettoyage", "автосервіс", "car service", "шиномонтаж", "tire service", "стоматолог", "dentist", "ветеринар", "veterinarian", "кур'єр", "courier"]),
        (.taxiCompare, ["найдешевше таксі", "дешевое такси", "cheapest taxi", "günstigstes taxi", "taxi le moins cher"]),
        (.groceryBasket, ["кошик", "корзин", "grocery basket", "warenkorb", "panier"]),
        (.fashionDiscovery, ["колекці", "collection", "kollektion"]),
        (.productSearch, ["знайди ", "найди ", "find ", "finde ", "trouve "]),
        (.show, ["покажи", "show ", "zeige", "montre"]),
        (.open, ["відкрий", "открой", "open ", "öffne", "ouvre"]),
        (.cancel, ["скасуй", "отмени", "cancel", "storniere", "annule"]),
        (.settings, ["налаштування", "настройки", "settings", "einstellungen", "réglages"]),
        (.help, ["допомога", "помощь", "help", "hilfe", "aide"])
    ]

    func parse(_ text: String) -> StructuredCommand {
        let normalized = normalize(text); let language = detectLanguage(normalized)
        guard !normalized.isEmpty else { return unknown(text, normalized, language) }
        let intent = Self.intentPatterns.first { _, patterns in patterns.contains { normalized.contains($0) } }?.0 ?? contextualIntent(normalized)
        var entities: [String: String] = [:]; var constraints = CommandConstraints()
        extractPrice(from: normalized, into: &constraints); extractSize(from: normalized, into: &constraints)
        extractFashionFilters(from: text, normalized: normalized, into: &constraints)
        constraints.ordinal = ordinal(in: normalized)
        if intent == .open, let target = target(after: ["відкрий", "открой", "open", "öffne", "ouvre"], in: text) { entities["app"] = target }
        if intent == .serviceSearch, let category = serviceCategory(in: normalized) { entities["serviceCategory"] = category }
        let risk: ActionRisk = intent == .emergency ? .emergency : ([.calendarCreate, .reminderCreate, .cancel, .undo].contains(intent) ? .reversible : .informational)
        return StructuredCommand(originalText: text, normalizedText: normalized, language: language, intent: intent, entities: entities, constraints: constraints, risk: risk, needsClarification: intent == .unknown)
    }

    private func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
    private func detectLanguage(_ text: String) -> CommandLanguage {
        if text.range(of: "[іїєґ]", options: .regularExpression) != nil { return .uk }
        if text.range(of: "[ыэъё]", options: .regularExpression) != nil { return .ru }
        if ["відкрий", "подзвони", "нагадай", "знайди", "скасуй", "покажи", "веди"].contains(where: text.contains) { return .uk }
        if ["открой", "позвони", "напомни", "найди", "отмени", "покажи"].contains(where: text.contains) { return .ru }
        if text.range(of: "[а-я]", options: .regularExpression) != nil { return .ru }
        if text.range(of: "[äöüß]", options: .regularExpression) != nil || ["öffne", "zeige", "erinnere", "einstellungen"].contains(where: text.contains) { return .de }
        if text.range(of: "[àâçéèêëîïôûùüÿœ]", options: .regularExpression) != nil || ["ouvre", "montre", "rappelle"].contains(where: text.contains) { return .fr }
        if text.range(of: "[a-z]", options: .regularExpression) != nil { return .en }
        return .automatic
    }
    private func contextualIntent(_ text: String) -> CommandIntent {
        ["другий", "друга", "второй", "second", "zweite", "deuxième", "цей", "this"].contains(text) ? .contextualSelection : .unknown
    }
    private func extractPrice(from text: String, into constraints: inout CommandConstraints) {
        let pattern = #"(?:до|max(?:imum)?|under|bis|jusqu['’]?à)\s*([0-9]+(?:[.,][0-9]+)?)\s*(грн|uah|usd|eur|€|\$|₴|гривень)?"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return }
        let match = String(text[range]); let parts = match.split(separator: " ")
        guard let numberToken = parts.first(where: { $0.contains(where: \.isNumber) }) else { return }
        constraints.maximumPrice = Decimal(string: numberToken.replacingOccurrences(of: ",", with: "."))
        if match.contains("eur") || match.contains("€") { constraints.currency = "EUR" }
        else if match.contains("usd") || match.contains("$") { constraints.currency = "USD" }
        else if match.contains("грн") || match.contains("uah") || match.contains("₴") || match.contains("гривень") { constraints.currency = "UAH" }
        constraints.hardConstraintKeys.insert("maximumPrice")
    }
    private func extractSize(from text: String, into constraints: inout CommandConstraints) {
        let patterns = [#"(?:розмір|размер|size|größe|taille)\s*([0-9]{1,3}|[xsml]{1,3})"#, #"([0-9]{2})\s*(?:розміру|размера)"#]
        for pattern in patterns {
            guard let match = text.range(of: pattern, options: .regularExpression) else { continue }
            let value = String(text[match]).split(separator: " ").first(where: { $0.contains(where: \.isNumber) || $0.allSatisfy { "xsml".contains($0) } })
            if let value { constraints.size = String(value); constraints.hardConstraintKeys.insert("size"); return }
        }
    }
    private func extractFashionFilters(from original: String, normalized text: String, into constraints: inout CommandConstraints) {
        let knownBrands = ["Baldinini", "Nike", "Adidas", "Puma", "Zara", "Mango", "Gucci", "Prada"]
        if let brand = knownBrands.first(where: { text.contains($0.lowercased()) }) {
            constraints.brand = brand; constraints.hardConstraintKeys.insert("brand")
        }
        let colors: [(String, [String])] = [
            ("black", ["чорн", "черн", "black", "schwarz", "noir"]),
            ("white", ["біл", "бел", "white", "weiß", "blanc"]),
            ("red", ["червон", "красн", "red", "rot", "rouge"]),
            ("blue", ["син", "blue", "blau", "bleu"])
        ]
        if let color = colors.first(where: { entry in entry.1.contains(where: text.contains) })?.0 {
            constraints.color = color; constraints.hardConstraintKeys.insert("color")
        }
        let categories: [(String, [String])] = [
            ("footwear", ["взут", "обув", "shoes", "footwear", "schuhe", "chaussures"]),
            ("clothing", ["одяг", "одеж", "clothing", "kleidung", "vêtement"]),
            ("accessories", ["аксесуар", "accessor", "zubehör", "accessoire"])
        ]
        if let category = categories.first(where: { entry in entry.1.contains(where: text.contains) })?.0 {
            constraints.category = category; constraints.hardConstraintKeys.insert("category")
        }
        let seasons = ["spring", "summer", "autumn", "winter"]
        let localizedSeasons = ["весн": "spring", "літ": "summer", "осін": "autumn", "зим": "winter"]
        if let season = seasons.first(where: text.contains) ?? localizedSeasons.first(where: { text.contains($0.key) })?.value {
            constraints.season = season; constraints.hardConstraintKeys.insert("season")
        }
        _ = original // Preserve original casing for future open-catalog brand extraction.
    }
    private func ordinal(in text: String) -> Int? {
        if ["другий", "друга", "второй", "second", "zweite", "deuxième"].contains(where: text.contains) { return 2 }
        if ["перший", "первая", "first", "erste", "premier"].contains(where: text.contains) { return 1 }
        return nil
    }
    private func serviceCategory(in text: String) -> String? {
        let values: [(String, [String])] = [
            ("towTruck", ["евакуатор", "tow truck", "abschlepp", "dépanneuse"]),
            ("plumber", ["сантехнік", "сантехник", "plumber", "klempner", "plombier"]),
            ("locksmith", ["слюсар", "locksmith", "schlüsseldienst", "serrurier"]),
            ("electrician", ["електрик", "электрик", "electrician", "elektriker", "électricien"]),
            ("cleaning", ["клінінг", "cleaning", "reinigung", "nettoyage"]),
            ("carService", ["автосервіс", "автосервис", "car service", "autoservice"]),
            ("tireService", ["шиномонтаж", "tire service", "reifenservice"]),
            ("dentist", ["стоматолог", "dentist", "zahnarzt", "dentiste"]),
            ("vet", ["ветеринар", "veterinarian", "tierarzt", "vétérinaire"]),
            ("courier", ["кур'єр", "курьер", "courier", "kurier", "coursier"])
        ]
        return values.first(where: { $0.1.contains(where: text.contains) })?.0
    }
    private func target(after prefixes: [String], in original: String) -> String? {
        let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let prefix = prefixes.first(where: { trimmed.lowercased().hasPrefix($0) }) else { return nil }
        let target = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return target.isEmpty ? nil : target
    }
    private func unknown(_ original: String, _ normalized: String, _ language: CommandLanguage) -> StructuredCommand {
        StructuredCommand(originalText: original, normalizedText: normalized, language: language, intent: .unknown, needsClarification: true)
    }
}
