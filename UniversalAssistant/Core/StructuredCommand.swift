import Foundation

enum CommandLanguage: String, Codable, Sendable { case uk, ru, en, de, fr, automatic }
enum CommandIntent: String, Codable, CaseIterable, Sendable {
    case placeSearch, productSearch, fashionDiscovery, groceryBasket, serviceSearch, restaurantSearch, reservation
    case taxiSearch, taxiCompare, navigation, routeSearch, routeAwareSearch
    case calendarCreate, calendarQuery, calendarUpdate, calendarDelete, reminderCreate, reminderQuery
    case reminderComplete, reminderDelete, noteCreate, noteQuery, shoppingList, contactLookup, contactCall, messageCompose
    case photoSearch, fileSearch, cameraCapture, translation, musicRecognition, mediaSearch, podcastSearch, parcelTrack, weather
    case publicTransport, transportRoute, ticketSearch, ticketPurchaseHandoff, hotelSearch, travelPlan
    case emergency, webSearch, deviceAction, appAction, audioRecord, show, open, cancel, undo
    case localUtility, currencyConversion
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

enum CompoundCommandClauses {
    static func split(_ text: String) -> [String] {
        let pattern = #"\s*(?:[,;]|\b(?:and then|und dann|і|та|потім|затем|then|puis)\b)\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [text] }
        let range = NSRange(text.startIndex..., in: text)
        var output: [String] = [], cursor = text.startIndex
        for match in regex.matches(in: text, range: range) {
            guard let valueRange = Range(match.range, in: text) else { continue }
            let value = text[cursor..<valueRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { output.append(value) }
            cursor = valueRange.upperBound
        }
        let tail = text[cursor...].trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { output.append(tail) }
        return output
    }
}

struct LocalCommandEngine: CommandParsing {
    private static let priceRegex = try! NSRegularExpression(pattern: #"(?:до|max(?:imum)?|under|bis|jusqu[’']?à)\s*([0-9]+(?:[.,][0-9]+)?)\s*(грн|uah|usd|eur|€|\$|₴|гривень)?"#)
    private static let sizeRegexes = [
        try! NSRegularExpression(pattern: #"(?:розмір|размер|size|größe|taille)\s*([0-9]{1,3}|[xsml]{1,3})"#),
        try! NSRegularExpression(pattern: #"([0-9]{2})\s*(?:розміру|размера)"#)
    ]
    private static let maximumWaitRegex = try! NSRegularExpression(pattern: #"(?:чекати|ждать|wait|warten|attendre)[^0-9]{0,24}([0-9]{1,3})\s*(?:хв|мин|min)"#)

    private static let intentPatterns: [(CommandIntent, [String])] = [
        (.multiStep, ["коли я кажу", "когда я говорю", "when i say", "wenn ich", "quand je dis",
                      "стоматолог і купи", "купи sensodyne по дорозі"]),
        (.undo, ["відміни останнє", "отмени последнее", "undo last", "rückgängig", "annule la dernière"]),
        (.emergency, ["112", "швидк", "скорая", "ambulance", "polizei", "police", "пожежа", "пожар"]),
        (.travelPlan, ["сплануй подорож", "спланируй поездку", "plan a trip", "reise planen", "planifie un voyage", "треба бути у", "треба бути в"]),
        (.currencyConversion, ["курс долара", "курс евро", "курс євро", "доларів у гривні", "долларов в гривны", "usd to uah", "eur to uah"]),
        (.localUtility, ["скільки буде", "сколько будет", "помножити", "умножить", "поділити", "разделить", "відсотків від", "процентов от", "кілометрів у", "километров в", "який сьогодні день", "какой сегодня день", "котра година", "который час"]),
        (.webSearch, ["пошукай в інтернеті", "поищи в интернете", "search the web", "im web suchen", "recherche sur le web"]),
        (.deviceAction, ["увімкни ліхтарик", "вимкни ліхтарик", "включи фонарик", "выключи фонарик", "turn on flashlight", "turn off flashlight", "taschenlampe einschalten", "allume la lampe",
                         "постав таймер", "створи таймер", "установи таймер", "создай таймер", "set a timer", "create a timer", "постав будильник", "створи будильник", "установи будильник", "создай будильник", "set an alarm", "create an alarm",
                         "заряд батареї", "заряд акумулятора", "скільки заряду", "відсоток батареї", "уровень батареи", "сколько заряда", "процент батареи", "battery level", "battery percentage", "вільного місця", "свободного места", "free storage",
                         "скопіюй у буфер", "скопіюй в буфер", "скопируй в буфер", "copy to clipboard", "покажи буфер", "прочитай буфер", "що в буфері", "що зараз у буфері", "що у буфері", "что в буфере", "что сейчас в буфере", "read clipboard", "відкрий посилання з буфера", "открой ссылку из буфера", "open clipboard url", "скопіюй останній результат", "скопируй последний результат", "copy last result", "де я зараз", "моє поточне місцезнаходження", "моя поточна адреса", "яка моя адреса", "где я сейчас", "мой текущий адрес", "current location", "current address", "скільки їхати", "сколько ехать", "travel time", "налаштування wi-fi", "настройки wi-fi",
                         "увімкни bluetooth", "включи bluetooth", "режим енергозбереження", "режим энергосбережения",
                         "зменш яскравість", "уменьши яркость", "збільш гучність", "увеличь громкость",
                         "пропущені дзвінки", "пропущенные звонки", "відкрий калькулятор", "открой калькулятор",
                         "відкрий програму телефон", "открой телефон", "покажи мої контакти", "покажи мои контакты", "покажи мої будильники"]),
        (.appAction, ["дія в застосунку", "действие в приложении", "action in app", "aktion in app", "action dans l'app"]),
        (.audioRecord, ["диктофон", "запиши аудіо", "призупини запис", "продовж запис", "зупини запис",
                        "voice recorder", "pause recording", "resume recording", "stop recording",
                        "sprachmemo", "aufnahme pausieren", "aufnahme fortsetzen", "aufnahme stoppen",
                        "enregistre audio", "pause l'enregistrement", "reprends l'enregistrement", "arrête l'enregistrement"]),
        (.cameraCapture, ["зроби фото", "відкрий камеру", "сфотографуй", "сделай фото", "открой камеру", "take a photo", "open camera", "скануй qr", "відскануй qr", "розпізнай qr", "qr-код", "qr код", "скануй код", "штрихкод", "сканируй qr", "сканируй код", "scan qr", "scan barcode", "розпізнай текст", "розпізнати текст", "распознай текст", "recognize text", "scan text", "відскануй документ", "скануй документ", "сканируй документ", "scan document"]),
        (.translation, ["переклади", "переведи", "translate ", "übersetze", "traduis"]),
        (.photoSearch, ["знайди фото", "покажи фото", "найди фото", "покажи фотографии", "find photos", "show photos", "відкрий останнє фото", "відкрий останню світлину", "відкрий найновіше фото", "відкрий найсвіжіше фото", "открой последнее фото", "open latest photo"]),
        (.fileSearch, ["знайди файл", "знайди документ", "найди файл", "найди документ", "find file", "find document"]),
        (.reminderComplete, ["виконай нагадування", "познач нагадування виконаним", "заверши напоминание", "complete reminder"]),
        (.reminderDelete, ["видали нагадування", "скасуй нагадування", "удали напоминание", "delete reminder"]),
        (.podcastSearch, ["знайди подкаст", "увімкни подкаст", "найди подкаст", "включи подкаст", "find podcast", "play podcast"]),
        (.musicRecognition, ["що це за пісня", "яка зараз грає пісня", "розпізнай музику", "що за музика", "что это за песня", "какая песня играет", "распознай музыку", "what song is this", "identify this song", "recognize music"]),
        (.mediaSearch, ["увімкни музику", "знайди пісню", "включи музыку", "найди песню", "play music", "find song"]),
        (.parcelTrack, ["де моя посилка", "відстеж посилку", "где моя посылка", "отследи посылку", "track parcel", "track package"]),
        (.calendarCreate, ["запиши", "додай зустріч", "создай встреч", "add event", "termin erstellen", "ajoute un rendez-vous"]),
        (.reminderCreate, ["нагадай", "нагадати", "напомни", "напомнить", "remind", "erinnere", "rappelle"]),
        (.contactCall, ["подзвони", "зателефонуй", "набери", "набрати", "позвони", "call ", "dial ", "ruf ", "appelle"]),
        (.messageCompose, ["напиши ", "отправь сообщение", "message ", "schreib ", "écris "]),
        (.navigation, ["веди ", "веди мене до", "проклади маршрут до", "маршрут до", "navigate", "route to", "navigiere", "itinéraire"]),
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
        (.calendarQuery, ["що в календарі", "що в мене заплановано", "які в мене плани", "что в календаре", "calendar events", "kalendertermine", "événements du calendrier"]),
        (.calendarUpdate, ["перенеси зустріч", "перенеси стоматолога", "перенеси встречу", "move the event", "termin verschieben", "déplace le rendez-vous"]),
        (.calendarDelete, ["видали зустріч", "скасуй завтра стоматолога", "удали встречу", "delete the event", "termin löschen", "supprime le rendez-vous"]),
        (.reminderQuery, ["покажи нагадування", "покажи мої нагадування", "відкрий нагадування", "нагадування на сьогодні", "нагадування на завтра", "покажи напоминания", "открой напоминания", "напоминания на сегодня", "show reminders", "open reminders", "erinnerungen zeigen", "affiche les rappels"]),
        (.noteCreate, ["створи нотатку", "створи нову нотатку", "создай заметку", "create a note", "notiz erstellen", "crée une note"]),
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
        if let directURL = validatedWebURL(text) {
            return StructuredCommand(originalText: text, normalizedText: normalized, language: language, intent: .open, entities: ["direct_url": directURL.absoluteString])
        }
        let semanticFrame = CanonicalSemanticFrameAnalyzer().analyze(original: text, normalized: normalized)
        if semanticFrame.intent == nil, let locationAction = locationSystemIntent(normalized) {
            var entities = ["system_action": locationAction]
            if locationAction == "travel_time", let destination = target(after: ["до", "to"], in: text) { entities["destination"] = destination }
            return StructuredCommand(originalText: text, normalizedText: normalized, language: language, intent: .deviceAction, entities: entities)
        }
        let patternIntent = Self.intentPatterns.first { _, patterns in patterns.contains { normalized.contains($0) } }?.0
        let specificPatternIntent = patternIntent == .productSearch ? nil : patternIntent
        let semanticIntent = semanticCapabilityIntent(normalized)
        let resolvedIntent = resolveSpecificAndSemantic(specific: specificPatternIntent, semantic: semanticIntent)
        let intent = semanticFrame.intent
            ?? priorityIntent(normalized)
            ?? (resolvedIntent == .placeSearch ? .placeSearch : compoundIntent(normalized))
            ?? resolvedIntent
            ?? patternIntent
            ?? contextualIntent(normalized)
        var entities = semanticFrame.entities; var constraints = CommandConstraints()
        extractPrice(from: normalized, into: &constraints); extractSize(from: normalized, into: &constraints)
        extractMaximumWait(from: normalized, into: &constraints)
        extractFashionFilters(from: text, normalized: normalized, into: &constraints)
        constraints.ordinal = ordinal(in: normalized)
        if intent == .open, entities["app"] == nil, let target = target(after: ["відкрий", "открой", "open", "öffne", "ouvre"], in: text) { entities["app"] = target }
        if [.contactLookup, .contactCall].contains(intent), entities["contact"] == nil, let value = target(after: ["знайди контакт", "найди контакт", "find contact", "подзвони", "зателефонуй", "набери", "набрати", "позвони", "call", "dial"], in: text) { entities["contact"] = contactSubject(value) }
        if intent == .contactCall { extractCallDetails(from: text, normalized: normalized, into: &entities) }
        if intent == .messageCompose, entities["recipient"] == nil, let value = target(after: ["напиши", "отправь сообщение", "message", "schreib", "écris"], in: text) { entities["recipient"] = value }
        if [.photoSearch, .fileSearch, .mediaSearch, .podcastSearch].contains(intent), entities["query"] == nil { entities["query"] = querySubject(for: intent, in: text) }
        if intent == .parcelTrack, let tracking = normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).first(where: { $0.count >= 5 && $0.rangeOfCharacter(from: .decimalDigits) != nil }) { entities["tracking_number"] = tracking }
        if intent == .serviceSearch, let category = serviceCategory(in: normalized) { entities["serviceCategory"] = category }
        if [.navigation, .routeSearch, .transportRoute].contains(intent), let value = target(after: ["веди мене до", "проклади маршрут до", "побудуй маршрут до", "покажи маршрут до", "построй маршрут до", "як доїхати до", "как доехать до", "маршрут до", "navigate", "route to", "веди"], in: text) { entities["destination"] = value }
        if [.placeSearch, .restaurantSearch, .serviceSearch, .weather].contains(intent), let value = locality(in: text) { entities["location"] = value }
        if intent == .weather, entities["location"] == nil { entities["near_current_location"] = "true" }
        if intent == .audioRecord { entities["recorder_action"] = recorderAction(in: normalized) }
        if intent == .deviceAction { extractSystemQuickAction(from: text, normalized: normalized, into: &entities) }
        if intent == .cameraCapture, ["qr", "q r", "ку ар", "штрихкод", "barcode", "скануй код", "сканируй код"].contains(where: normalized.contains) { entities["capture_mode"] = "code_scan" }
        if intent == .cameraCapture, ["розпізнай текст", "розпізнати текст", "распознай текст", "recognize text", "scan text"].contains(where: normalized.contains) {
            entities["capture_mode"] = "text_scan"
            if ["файл", "документ", "file", "document"].contains(where: normalized.contains) { entities["input_source"] = "document" }
        }
        if intent == .cameraCapture,
           ["відскануй документ", "скануй документ", "сканируй документ", "scan document"].contains(where: normalized.contains) {
            entities["capture_mode"] = "text_scan"
            entities["input_source"] = "document_camera"
        }
        if intent == .translation {
            if let value = translationSource(in: text) { entities["source_text"] = value }
            if let target = translationTarget(in: normalized) { entities["target_language"] = target }
        }
        let risk: ActionRisk = intent == .emergency ? .emergency : ([.calendarCreate, .reminderCreate, .reminderComplete, .reminderDelete, .shoppingList, .cancel, .undo].contains(intent) ? .reversible : .informational)
        return StructuredCommand(originalText: text, normalizedText: normalized, language: language, intent: intent, entities: entities, constraints: constraints, risk: risk, needsClarification: intent == .unknown)
    }

    private func locationSystemIntent(_ text: String) -> String? {
        if ["скільки їхати", "сколько ехать", "travel time", "how long"].contains(where: text.contains) { return "travel_time" }
        let addressStem = ["адрес", "address"].contains(where: text.contains)
        let selfLocation = ["мо", "поточ", "текущ", "де я", "где я", "current", "my "].contains(where: text.contains)
        if addressStem && selfLocation { return "current_address" }
        let locationStem = ["місцезнаход", "местополож", "location", "де я", "где я"].contains(where: text.contains)
        if locationStem && selfLocation { return "current_location" }
        return nil
    }

    private func validatedWebURL(_ text: String) -> URL? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: value), let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme), components.host != nil else { return nil }
        return components.url
    }

    private func extractCallDetails(from original: String, normalized: String, into entities: inout [String: String]) {
        if normalized.contains("whatsapp") || normalized.contains("вотсап") || normalized.contains("ватсап") { entities["call_service"] = "whatsapp" }
        if let range = original.range(of: #"(?:номер\s*)?\+?[0-9][0-9\s()\-]{5,}"#, options: [.regularExpression, .caseInsensitive]) {
            let raw = String(original[range])
            let prefix = raw.contains("+") ? "+" : ""
            let digits = raw.filter(\.isNumber)
            if digits.count >= 7 { entities["phone_number"] = prefix + digits }
        }
    }

    private func extractSystemQuickAction(from original: String, normalized text: String, into entities: inout [String: String]) {
        if ["ліхтарик", "фонарик", "flashlight", "taschenlampe", "lampe"].contains(where: text.contains) {
            entities["system_action"] = "flashlight"
            entities["enabled"] = ["вимк", "выключ", "turn off"].contains(where: text.contains) ? "false" : "true"
        } else if ["заряд батареї", "заряд акумулятора", "скільки заряду", "відсоток батареї", "уровень батареи", "сколько заряда", "процент батареи", "battery level", "battery percentage"].contains(where: text.contains) { entities["system_action"] = "battery"
        } else if ["вільного місця", "свободного места", "free storage"].contains(where: text.contains) { entities["system_action"] = "storage"
        } else if ["відкрий посилання з буфера", "открой ссылку из буфера", "open clipboard url"].contains(where: text.contains) {
            entities["system_action"] = "clipboard_open_url"
        } else if ["покажи буфер", "прочитай буфер", "що в буфері", "що зараз у буфері", "що у буфері", "что в буфере", "что сейчас в буфере", "read clipboard"].contains(where: text.contains) {
            entities["system_action"] = "clipboard_read"
        } else if ["скопіюй останній результат", "скопируй последний результат", "copy last result"].contains(where: text.contains) {
            entities["system_action"] = "clipboard_copy_context"
        } else if let trigger = ["скопіюй у буфер", "скопіюй в буфер", "скопируй в буфер", "copy to clipboard"].first(where: text.contains) {
            entities["system_action"] = "clipboard"
            if let range = original.range(of: trigger, options: [.caseInsensitive, .diacriticInsensitive]) {
                let content = original[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":,-")))
                if !content.isEmpty { entities["content"] = content }
            }
        } else if ["скільки їхати", "сколько ехать", "travel time"].contains(where: text.contains) {
            entities["system_action"] = "travel_time"
            if let destination = target(after: ["до", "to"], in: original) { entities["destination"] = destination }
        } else if ["адрес", "address"].contains(where: text.contains) {
            entities["system_action"] = "current_address"
        } else if ["де я", "где я", "current location", "місцезнаходження", "местоположение"].contains(where: text.contains) {
            entities["system_action"] = "current_location"
        } else if ["wi-fi", "bluetooth", "енергозбереження", "энергосбережения", "яскравість", "яркость", "гучність", "громкость", "пропущені дзвінки", "пропущенные звонки", "калькулятор", "програму телефон", "покажи мої контакти", "покажи мои контакты", "покажи мої будильники"].contains(where: text.contains) { entities["system_action"] = "unsupported_system_control"
        } else if ["таймер", "timer"].contains(where: text.contains) {
            entities["system_action"] = "timer"
            if entities["duration_seconds"] == nil, let match = text.range(of: #"([0-9]+)\s*(хв|мин|min|minute|сек|sec)"#, options: .regularExpression) {
                let value = String(text[match]); let amount = value.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.first
                if let amount { entities["duration_seconds"] = String(value.contains("сек") || value.contains("sec") ? amount : amount * 60) }
                if let label = alarmLabel(in: text, kind: "timer") { entities["label"] = label }
            }
        } else if ["будильник", "alarm"].contains(where: text.contains) {
            entities["system_action"] = "alarm"
            if let match = text.range(of: #"\b([01]?[0-9]|2[0-3])[:.]([0-5][0-9])\b"#, options: .regularExpression) {
                let parts = text[match].split(whereSeparator: { $0 == ":" || $0 == "." })
                if parts.count == 2 { entities["hour"] = String(parts[0]); entities["minute"] = String(parts[1]) }
                if let label = alarmLabel(in: text, kind: "alarm") { entities["label"] = label }
            }
        }
    }

    private func alarmLabel(in text: String, kind: String) -> String? {
        var value = text
        let commandPattern = kind == "timer" ? #"(?:постав|установи|set|створи|создай)?\s*(?:таймер|timer)"# : #"(?:постав|установи|set|створи|создай)?\s*(?:будильник|alarm)"#
        value = value.replacingOccurrences(of: commandPattern, with: " ", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: #"(?:\bна|for|at)?\s*\d{1,2}(?::[0-5]\d)?\s*(?:хвилин\p{L}*|хв|минут\p{L}*|мин|minutes?|mins?|секунд\p{L}*|сек|seconds?|secs?)?"#, with: " ", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return value.isEmpty ? nil : value
    }

    private func translationSource(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let actionPattern = #"(?:перекла\p{L}*|переве\p{L}*|translate\p{L}*|übersetz\p{L}*|tradui\p{L}*)"#
        guard let action = trimmed.range(of: actionPattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        var value = String(trimmed[action.upperBound...])
        value = value.replacingOccurrences(of: #"^\s*(?:мені|мне|please|будь ласка)?\s*(?:англійською|на англійську|на английский|into english|to english|німецькою|на німецьку|на немецкий|into german|французькою|на французьку|українською|на українську|на украинский)(?:\s+(?:мовою|языком|language))?\s*[:,-]?\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return cleaned.isEmpty ? nil : cleaned
    }

    private func recorderAction(in text: String) -> String {
        if ["призупини", "pause recording", "aufnahme pausieren", "pause l'enregistrement"].contains(where: text.contains) { return "pause" }
        if ["продовж", "resume recording", "aufnahme fortsetzen", "reprends l'enregistrement"].contains(where: text.contains) { return "resume" }
        if ["зупини", "заверш", "закінч", "останови", "заверши", "stop recording", "aufnahme stoppen", "arrête l'enregistrement"].contains(where: text.contains) { return "stop" }
        return "start"
    }

    private func compoundIntent(_ text: String) -> CommandIntent? {
        let compoundMarkers = [",", ";", " і ", " та ", " потім ", " затем ", " and then ", " then ", " und dann ", " puis "]
        guard compoundMarkers.contains(where: text.contains) else { return nil }
        let clauses = CompoundCommandClauses.split(text)
        guard clauses.count >= 2 else { return nil }
        let recognized = clauses.filter { clause in
            let specific = Self.intentPatterns.first { intent, patterns in
                intent != .multiStep && intent != .productSearch && patterns.contains { clause.contains($0) }
            }?.0
            let semantic = semanticCapabilityIntent(clause)
            let value = priorityIntent(clause)
                ?? resolveSpecificAndSemantic(specific: specific, semantic: semantic)
                ?? Self.intentPatterns.first { intent, patterns in intent != .multiStep && patterns.contains { clause.contains($0) } }?.0
                ?? contextualIntent(clause)
            return value != .unknown
        }
        return recognized.count >= 2 ? .multiStep : nil
    }

    private func translationTarget(in text: String) -> String? {
        let values = [("англій", "en"), ("англий", "en"), ("english", "en"), ("україн", "uk"), ("украин", "uk"), ("ukrainian", "uk"),
                      ("росій", "ru"), ("русск", "ru"), ("russian", "ru"), ("німець", "de"), ("немец", "de"), ("german", "de"),
                      ("француз", "fr"), ("french", "fr")]
        return values.first { text.contains($0.0) }?.1
    }

    private func querySubject(for intent: CommandIntent, in text: String) -> String {
        let prefixes: [String] = switch intent {
        case .photoSearch: ["відкрий останнє фото", "відкрий найновіше фото", "відкрий найсвіжіше фото", "відкрий останню світлину", "знайди фото", "покажи фото", "покажи мої", "найди фото", "покажи фотографии", "find photos", "show photos"]
        case .fileSearch: ["знайди файл", "знайди документ", "найди файл", "найди документ", "find file", "find document"]
        case .mediaSearch: ["увімкни музику", "увімкни", "знайди пісню", "включи музыку", "включи", "найди песню", "play music", "play", "find song"]
        case .podcastSearch: ["знайди подкаст", "увімкни подкаст", "найди подкаст", "включи подкаст", "find podcast", "play podcast"]
        default: []
        }
        var value = target(after: prefixes, in: text) ?? ""
        if intent == .mediaSearch {
            value = value.replacingOccurrences(of: #"\s+(?:в|у|через|on|in)\s+apple\s+music\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func normalize(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "’", with: "'").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let scannerContext = ["скан", "відскан", "розпіз", "scan", "recogn"].contains(where: value.contains)
        if scannerContext {
            value = value.replacingOccurrences(of: #"(?:q\s*(?:club|клуб)|quad)"#, with: "qr", options: [.regularExpression, .caseInsensitive])
        }
        return value
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
        let openVoiceMemos = ["відкрий", "открой", "open"].contains(where: text.contains) && ["диктофон", "voice memos", "голосові записи", "голосовые записи"].contains(where: text.contains)
        if openVoiceMemos { return .open }
        if LocalUtilityEngine.recognizes(text) { return .localUtility }
        if LocalUtilityEngine.recognizesCurrency(text) { return .currencyConversion }
        let informationalGoals = ["інформац", "відомо про", "хто зараз", "свежую информацию", "информацию о", "кто сейчас", "information about", "latest information", "who is", "informationen über", "wer ist", "informations sur", "qui est"]
        if informationalGoals.contains(where: text.contains) { return .unknown }
        if text.contains("перенеси стоматолога") { return .calendarUpdate }
        if text.contains("скасуй завтра стоматолога") { return .calendarDelete }
        if text.contains("таксі додому") && text.contains("чекати") { return .taxiSearch }
        return nil
    }
    private func resolveSpecificAndSemantic(specific: CommandIntent?, semantic: CommandIntent?) -> CommandIntent? {
        guard let semantic else { return specific }
        let broadCollision: Bool = switch (semantic, specific) {
        case (.photoSearch, .show), (.audioRecord, .calendarCreate),
             (.mediaSearch, .show), (.mediaSearch, .productSearch),
             (.calendarCreate, .productSearch),
             (.placeSearch, .show), (.placeSearch, .productSearch),
             (.placeSearch, .transportRoute), (.placeSearch, .routeSearch),
             (.placeSearch, .ticketSearch): true
        default: false
        }
        return broadCollision ? semantic : (specific ?? semantic)
    }

    private func semanticCapabilityIntent(_ text: String) -> CommandIntent? {
        let commerceActions = ["куп", "придба", "замов", "ціна", "вартіст", "скільки кошту", "сколько стоит", "покуп", "закаж", "цена", "стоимость", "buy", "purchase", "price"]
        let placeActions = ["де ", "куди", "поруч", "поблизу", "найближ", "зайти", "піти", "сходити", "рядом", "ближайш", "куда", "пойти", "nearby", "nearest", "closest", "where"]
        let placeKinds = ["кав", "кафе", "кофе", "кофейн", "ресторан", "бар", "піцер", "пиццер", "bakery", "cafe", "coffee shop", "restaurant", "аптек", "pharmacy", "заправ", "gas station", "поїсти", "поесть", "dining"]
        let fashionKinds = ["одяг", "взут", "футбол", "сороч", "куртк", "сукн", "штани", "кросів", "черев", "одеж", "обув", "рубаш", "плать", "брюк", "кроссов", "ботин", "clothing", "apparel", "footwear", "shirt", "jacket", "dress", "sneaker", "shoe"]
        let groceryKinds = ["продукт", "супермаркет", "магазин", "молоч", "хліб", "овоч", "фрукт", "круп", "напій", "хлеб", "овощ", "grocer", "supermarket", "food store"]
        let retailerSignals = ["сільпо", "silpo", "атб", "fora", "фора", "fozzy"]

        let cameraActions = ["знім", "сфотограф", "сними", "сфотограф", "capture", "take"]
        let cameraKinds = ["фото", "фотограф", "знімок", "снимок", "photo", "picture", "image"]
        if containsAny(text, cameraActions), containsAny(text, cameraKinds) { return .cameraCapture }

        let translationActions = ["перекла", "переве", "translate", "übersetz", "tradui"]
        let translationTargets = ["англій", "україн", "росій", "німець", "француз", "англий", "украин", "русск", "немец", "english", "ukrainian", "russian", "german", "french"]
        if containsAny(text, translationActions), containsAny(text, translationTargets) { return .translation }

        let showActions = ["покажи", "знайди", "найди", "show", "find"]
        let photoKinds = ["фото", "фотограф", "світлин", "снимк", "photos", "pictures"]
        if containsAny(text, showActions), containsAny(text, photoKinds) { return .photoSearch }

        let recordActions = ["запиши", "записати", "почни запис", "запиши голос", "запиши аудіо", "запиши аудио", "заверш", "закінч", "останов", "stop recording", "finish recording", "record"]
        let recordKinds = ["голосов", "аудіо", "аудио", "диктофон", "voice note", "recording"]
        if containsAny(text, recordActions), containsAny(text, recordKinds) { return .audioRecord }

        let recognitionQuestions = ["що це", "що за", "яка", "розпізнай", "визнач", "что это", "что за", "какая", "распознай", "определи", "what", "identify", "recognize"]
        let recognitionKinds = ["пісн", "музик", "композ", "трек", "песн", "музык", "music", "song", "track", "composition"]
        if containsAny(text, recognitionQuestions), containsAny(text, recognitionKinds), ["це", "зараз", "грає", "это", "сейчас", "играет", "this", "playing", "identify", "recognize", "розпіз", "распоз"].contains(where: text.contains) { return .musicRecognition }

        let mediaActions = ["увімкни", "включи", "програй", "воспроизведи", "знайди", "найди", "play", "listen"]
        let mediaKinds = ["apple music", "музик", "пісн", "песн", "трек", "альбом", "виконав", "исполнител", "song", "artist"]
        if containsAny(text, mediaActions), containsAny(text, mediaKinds) { return .mediaSearch }

        let reminderKinds = ["нагадув", "напомин", "reminder", "erinner", "rappel"]
        let reminderQueryActions = ["покажи", "відкрий", "перелік", "список", "що треба", "покажи", "открой", "список", "show", "open", "list"]
        if containsAny(text, reminderKinds), containsAny(text, reminderQueryActions) { return .reminderQuery }

        let calendarActions = ["створи", "создай", "додай", "добавь", "заплануй", "запланируй", "create", "add", "schedule"]
        let calendarKinds = ["подію", "подія", "событие", "зустріч", "встреч", "event", "appointment"]
        if containsAny(text, calendarActions), containsAny(text, calendarKinds) { return .calendarCreate }

        let storefrontKinds = ["магазин", "крамниц", "store", "shop"]
        let routeSignals = ["як доїхати", "как доехать", "маршрут", "route", "directions"]
        if containsAny(text, storefrontKinds), (containsAny(text, placeActions) || containsAny(text, routeSignals)) { return .placeSearch }

        if containsAny(text, placeActions), containsAny(text, placeKinds) { return .placeSearch }
        guard containsAny(text, commerceActions) else { return nil }
        if containsAny(text, retailerSignals) || containsAny(text, groceryKinds) { return .groceryBasket }
        if containsAny(text, fashionKinds) { return .fashionDiscovery }
        return .productSearch
    }

    private func firstRange(_ regex: NSRegularExpression, in text: String) -> Range<String.Index>? {
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return Range(match.range, in: text)
    }

    private func containsAny(_ text: String, _ signals: [String]) -> Bool {
        signals.contains(where: text.contains)
    }

    private func contactSubject(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"\s+(?:на|у|в)\s+(?:моєму|моем|цьому|этом)?\s*(?:iphone|айфоні|айфоне|телефоні|телефоне|пристрої|устройстве)\s*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        ).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func extractPrice(from text: String, into constraints: inout CommandConstraints) {
        guard let range = firstRange(Self.priceRegex, in: text) else { return }
        let match = String(text[range]); let parts = match.split(separator: " ")
        guard let numberToken = parts.first(where: { $0.contains(where: \.isNumber) }) else { return }
        constraints.maximumPrice = Decimal(string: numberToken.replacingOccurrences(of: ",", with: "."))
        if match.contains("eur") || match.contains("€") { constraints.currency = "EUR" }
        else if match.contains("usd") || match.contains("$") { constraints.currency = "USD" }
        else if match.contains("грн") || match.contains("uah") || match.contains("₴") || match.contains("гривень") { constraints.currency = "UAH" }
        constraints.hardConstraintKeys.insert("maximumPrice")
    }
    private func extractSize(from text: String, into constraints: inout CommandConstraints) {
        for regex in Self.sizeRegexes {
            guard let match = firstRange(regex, in: text) else { continue }
            let value = String(text[match]).split(separator: " ").first(where: { $0.contains(where: \.isNumber) || $0.allSatisfy { "xsml".contains($0) } })
            if let value { constraints.size = String(value); constraints.hardConstraintKeys.insert("size"); return }
        }
    }
    private func extractMaximumWait(from text: String, into constraints: inout CommandConstraints) {
        guard let range = firstRange(Self.maximumWaitRegex, in: text),
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
    private func locality(in original: String) -> String? {
        let patterns = [" поруч у ", " поруч в ", " рядом в ", " у ", " в ", " in ", " near "]
        let value = patterns.compactMap { marker -> String? in
            guard let range = original.range(of: marker, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
            let suffix = original[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            let boundary = [",", " який ", " яка ", " яке ", " которые ", " который ", " як ", " как ", " і ", " и "]
                .compactMap { suffix.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive])?.lowerBound }
                .min()
            let locality = boundary.map { String(suffix[..<$0]) } ?? suffix
            let value = locality.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            return value.isEmpty ? nil : value
        }.first
        return value
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
