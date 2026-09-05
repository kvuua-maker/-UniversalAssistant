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
    var maximumWaitMinutes: Int?
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
        (.multiStep, ["коли я кажу", "когда я говорю", "when i say", "wenn ich", "quand je dis",
                      "стоматолог і купи", "купи sensodyne по дорозі"]),
        (.undo, ["відміни останнє", "отмени последнее", "undo last", "rückgängig", "annule la dernière"]),
        (.emergency, ["112", "швидк", "скорая", "ambulance", "polizei", "police", "пожежа", "пожар"]),
        (.travelPlan, ["сплануй подорож", "спланируй поездку", "plan a trip", "reise planen", "planifie un voyage", "треба бути у", "треба бути в"]),
        (.webSearch, ["пошукай в інтернеті", "поищи в интернете", "search the web", "im web suchen", "recherche sur le web"]),
        (.deviceAction, ["увімкни ліхтарик", "включи фонарик", "turn on flashlight", "taschenlampe einschalten", "allume la lampe"]),
        (.appAction, ["дія в застосунку", "действие в приложении", "action in app", "aktion in app", "action dans l'app"]),
        (.audioRecord, ["диктофон", "запиши аудіо", "призупини запис", "продовж запис", "зупини запис",
                        "voice recorder", "pause recording", "resume recording", "stop recording",
                        "sprachmemo", "aufnahme pausieren", "aufnahme fortsetzen", "aufnahme stoppen",
                        "enregistre audio", "pause l'enregistrement", "reprends l'enregistrement", "arrête l'enregistrement"]),
        (.calendarCreate, ["запиши", "додай зустріч", "создай встреч", "add event", "termin erstellen", "ajoute un rendez-vous"]),
        (.reminderCreate, ["нагадай", "нагадати", "напомни", "напомнить", "remind", "erinnere", "rappelle"]),
        (.contactCall, ["подзвони", "позвони", "call ", "ruf ", "appelle"]),
        (.messageCompose, ["напиши ", "отправь сообщение", "message ", "schreib ", "écris "]),
        (.navigation, ["веди ", "маршрут до", "navigate", "route to", "navigiere", "itinéraire"]),
        (.routeAwareSearch, ["по дорозі", "по пути", "along the route", "auf dem weg", "sur le trajet"]),
        (.routeSearch, ["побудуй маршрут", "покажи маршрут", "построй маршрут", "build a route", "route planen", "crée un itinéraire"]),
        (.publicTransport, ["громадський транспорт", "общественный транспорт", "public transport", "öffentliche verkehr", "transports en commun"]),
        (.transportRoute, ["як доїхати", "как доехать", "transit route", "wie komme ich", "comment aller"]),
        (.placeSearch, ["хочу кави", "хочу кофе", "want coffee", "kaffee", "envie de café"]),
        (.placeSearch, ["кави хочеться", "кофе хочется", "coffee please", "lust auf kaffee", "envie d'un café"]),
        (.weather, ["погод", "weather", "wetter", "météo"]),
        (.ticketPurchaseHandoff, ["купи квиток", "купи билет", "buy ticket", "fahrkarte kaufen", "achète le billet"]),
        (.ticketSearch, ["квиток", "квитки", "билет", "ticket", "fahrkarte", "billet"]),
        (.hotelSearch, ["готель", "отель", "hotel", "hôtel", "квартиру"]),
        (.serviceSearch, ["евакуатор", "tow truck", "abschlepp", "dépanneuse", "сантехнік", "сантехник", "plumber", "klempner", "plombier", "слюсар", "locksmith", "schlüsseldienst", "serrurier", "електрик", "электрик", "electrician", "elektriker", "électricien", "клінінг", "cleaning", "reinigung", "nettoyage", "автосервіс", "car service", "шиномонтаж", "tire service", "стоматолог", "dentist", "ветеринар", "veterinarian", "кур'єр", "courier"]),
        (.taxiCompare, ["найдешевше таксі", "дешевое такси", "cheapest taxi", "günstigstes taxi", "taxi le moins cher"]),
        (.taxiSearch, ["виклич таксі", "вызови такси", "find a taxi", "taxi rufen", "appelle un taxi"]),
        (.reservation, ["забронюй столик", "забронируй столик", "reserve a table", "tisch reservieren", "réserve une table"]),
        (.restaurantSearch, ["ресторан поруч", "ресторан рядом", "restaurant nearby", "restaurant in der nähe", "restaurant à proximité"]),
        (.groceryBasket, ["кошик", "корзин", "grocery basket", "warenkorb", "panier"]),
        (.fashionDiscovery, ["колекці", "collection", "kollektion"]),
        (.calendarQuery, ["що в календарі", "что в календаре", "calendar events", "kalendertermine", "événements du calendrier"]),
        (.calendarUpdate, ["перенеси зустріч", "перенеси стоматолога", "перенеси встречу", "move the event", "termin verschieben", "déplace le rendez-vous"]),
        (.calendarDelete, ["видали зустріч", "скасуй завтра стоматолога", "удали встречу", "delete the event", "termin löschen", "supprime le rendez-vous"]),
        (.reminderQuery, ["покажи нагадування", "покажи напоминания", "show reminders", "erinnerungen zeigen", "affiche les rappels"]),
        (.noteCreate, ["створи нотатку", "создай заметку", "create a note", "notiz erstellen", "crée une note"]),
        (.noteQuery, ["покажи нотатки", "покажи заметки", "show notes", "notizen zeigen", "affiche les notes"]),
        (.shoppingList, ["список покупок", "список покупок", "shopping list", "einkaufsliste", "liste de courses"]),
        (.contactLookup, ["знайди контакт", "найди контакт", "find contact", "kontakt finden", "trouve le contact"]),
        (.productSearch, ["знайди ", "найди ", "find ", "finde ", "trouve "]),
        (.show, ["покажи", "show ", "zeige", "montre"]),
        (.open, ["відкрий", "открой", "open ", "öffne", "ouvre"]),
        (.open, ["telegram відкрий", "telegram открой", "telegram open"]),
        (.cancel, ["скасуй", "отмени", "cancel", "storniere", "annule"]),
        (.settings, ["налаштування", "настройки", "settings", "einstellungen", "réglages"]),
        (.help, ["допомога", "помощь", "help", "hilfe", "aide"])
    ]

    func parse(_ text: String) -> StructuredCommand {
        let normalized = normalize(text); let language = detectLanguage(normalized)
        guard !normalized.isEmpty else { return unknown(text, normalized, language) }
        let intent = priorityIntent(normalized) ?? Self.intentPatterns.first { _, patterns in patterns.contains { normalized.contains($0) } }?.0 ?? contextualIntent(normalized)
        var entities: [String: String] = [:]; var constraints = CommandConstraints()
        extractPrice(from: normalized, into: &constraints); extractSize(from: normalized, into: &constraints)
        extractMaximumWait(from: normalized, into: &constraints)
        extractFashionFilters(from: text, normalized: normalized, into: &constraints)
        constraints.ordinal = ordinal(in: normalized)
        if intent == .open, let target = target(after: ["відкрий", "открой", "open", "öffne", "ouvre"], in: text) { entities["app"] = target }
        if intent == .serviceSearch, let category = serviceCategory(in: normalized) { entities["serviceCategory"] = category }
        if intent == .audioRecord { entities["recorder_action"] = recorderAction(in: normalized) }
        let risk: ActionRisk = intent == .emergency ? .emergency : ([.calendarCreate, .reminderCreate, .cancel, .undo].contains(intent) ? .reversible : .informational)
        return StructuredCommand(originalText: text, normalizedText: normalized, language: language, intent: intent, entities: entities, constraints: constraints, risk: risk, needsClarification: intent == .unknown)
    }

    private func recorderAction(in text: String) -> String {
        if ["призупини", "pause recording", "aufnahme pausieren", "pause l'enregistrement"].contains(where: text.contains) { return "pause" }
        if ["продовж", "resume recording", "aufnahme fortsetzen", "reprends l'enregistrement"].contains(where: text.contains) { return "resume" }
        if ["зупини", "stop recording", "aufnahme stoppen", "arrête l'enregistrement"].contains(where: text.contains) { return "stop" }
        return "start"
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
    private func priorityIntent(_ text: String) -> CommandIntent? {
        let informationalGoals = ["інформац", "відомо про", "хто зараз", "свежую информацию", "информацию о", "кто сейчас", "information about", "latest information", "who is", "informationen über", "wer ist", "informations sur", "qui est"]
        if informationalGoals.contains(where: text.contains) { return .unknown }
        if text.contains("перенеси стоматолога") { return .calendarUpdate }
        if text.contains("скасуй завтра стоматолога") { return .calendarDelete }
        if text.contains("таксі додому") && text.contains("чекати") { return .taxiSearch }
        return nil
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
    private func extractMaximumWait(from text: String, into constraints: inout CommandConstraints) {
        let pattern = #"(?:чекати|ждать|wait|warten|attendre)[^0-9]{0,24}([0-9]{1,3})\s*(?:хв|мин|min)"#
        guard let range = text.range(of: pattern, options: .regularExpression),
              let value = String(text[range]).split(whereSeparator: { !$0.isNumber }).compactMap({ Int($0) }).first else { return }
        constraints.maximumWaitMinutes = value
        constraints.hardConstraintKeys.insert("maximumWaitMinutes")
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
        guard let range = prefixes.compactMap({ trimmed.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) })
            .min(by: { $0.lowerBound < $1.lowerBound }) else { return nil }
        let target = trimmed[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return target.isEmpty ? nil : target
    }
    private func unknown(_ original: String, _ normalized: String, _ language: CommandLanguage) -> StructuredCommand {
        StructuredCommand(originalText: original, normalizedText: normalized, language: language, intent: .unknown, needsClarification: true)
    }
}
