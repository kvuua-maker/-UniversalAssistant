import Foundation

/// A role-preserving interpretation produced before capability selection.
/// It intentionally describes the whole command instead of treating any one
/// noun (for example “document”) as an intent.
struct CanonicalSemanticFrame: Equatable, Sendable {
    enum Action: String, Sendable { case open, choose, search, show, create, update, delete, copy, call, message, scan, recognize, share, navigate, query, set, record }
    enum Object: String, Sendable { case file, photo, document, contact, calendar, reminder, timer, alarm, app, settings, battery, storage, url, place, weather, travelTime, text, code, note, audio, media }
    enum Source: String, Sendable { case files, photos, documents, clipboard, camera, calendar, reminders }
    enum ContextReference: String, Sendable { case currentLocation, activeRoute, selectedResult, sharedContent, previousResult }

    struct TemporalRole: Equatable, Sendable {
        let expression: String
        let durationSeconds: Int?
        let hour: Int?
        let minute: Int?
        let dayPeriod: String?
    }
    struct NumericRole: Equatable, Sendable { let orderedTokens: [String]; let percentage: Decimal? }
    struct CompoundRole: Equatable, Sendable { let clauses: [String]; let isSequential: Bool }

    var action: Action?
    var object: Object?
    var source: Source?
    var service: String?
    var entityAmbiguity: [String] = []
    var person: String?
    var app: String?
    var location: String?
    var temporal: TemporalRole?
    var numeric: NumericRole?
    var contextReference: ContextReference?
    var compound: CompoundRole?
    var modifiers: Set<String> = []
    var confidence: Double = 0
}

struct CanonicalSemanticFrameResult: Equatable, Sendable {
    let frame: CanonicalSemanticFrame
    let intent: CommandIntent?
    let entities: [String: String]
}

struct CanonicalSemanticFrameAnalyzer: Sendable {
    private static let numericRegex = try! NSRegularExpression(pattern: #"[-+]?\d+(?:[.,]\d+)?"#)
    private static let percentageRegex = try! NSRegularExpression(
        pattern: #"([-+]?\d+(?:[.,]\d+)?)\s*(?:%|відсот\p{L}*|процент\p{L}*|percent\p{L}*)"#,
        options: [.caseInsensitive]
    )

    func analyze(original: String, normalized: String) -> CanonicalSemanticFrameResult {
        let tokens = lexicalTokens(normalized)
        var frame = CanonicalSemanticFrame()
        frame.action = action(in: tokens)
        frame.object = object(in: tokens)
        if isApplicationSettingsRequest(tokens: tokens, normalized: normalized) {
            frame.object = .settings
        }
        let hasVisualObject = tokens.contains { token in
            ["фото", "світлин", "знім", "сним", "photo", "image", "picture"].contains { token.hasPrefix($0) }
        }
        // In a command such as “read text on the image”, text is the requested
        // output while the visual asset is the source/target. OBJECT ordering
        // must not redirect that composition to a camera-only OCR command.
        if frame.action == .recognize && hasVisualObject { frame.object = .photo }
        frame.source = source(in: tokens)
        if frame.object == .text, frame.action == .recognize,
           tokens.contains(where: { $0.hasPrefix("документ") || $0.hasPrefix("document") }) {
            frame.source = .documents
        }
        // Messenger recovery is meaningful only after the structural action
        // establishes a CALL/MESSAGE service role. Running fuzzy recovery over
        // every token in unrelated commands can manufacture an ambiguity.
        if frame.action == .call || frame.action == .message {
            switch service(in: tokens) {
            case let .resolved(service): frame.service = service.rawValue
            case let .ambiguous(values): frame.entityAmbiguity = values
            case .unresolved: break
            }
        }
        frame.app = application(in: tokens)
        frame.modifiers = modifiers(in: tokens)

        if frame.object == .contact || frame.action == .call || frame.action == .message {
            frame.person = trailingEntity(
                original,
                afterActionFamilies: [
                    ["контакт", "contact"], ["подзвон", "зателефон", "набер", "позвон", "call", "dial"],
                    ["напиш", "надішл", "відправ", "повідом", "сообщ", "message", "send"]
                ],
                stoppingAt: [" через ", " у whatsapp", " в whatsapp", " via whatsapp", " по whatsapp"]
            )
        }
        frame.location = locationPhrase(in: original)
        if frame.action == .navigate, frame.location == nil {
            frame.location = navigationDestination(in: original)
        }
        frame.temporal = temporalRole(in: original, normalized: normalized)
        frame.numeric = numericRole(in: normalized)
        frame.contextReference = contextReference(in: normalized)
        frame.compound = compoundRole(in: original, normalized: normalized)

        let resolved = resolve(frame: frame, original: original, normalized: normalized)
        frame.confidence = resolved.0 == nil ? 0 : confidence(frame)
        return .init(frame: frame, intent: resolved.0, entities: resolved.1)
    }

    private func resolve(
        frame: CanonicalSemanticFrame,
        original: String,
        normalized: String
    ) -> (CommandIntent?, [String: String]) {
        var entities: [String: String] = [:]
        if let temporal = frame.temporal {
            entities["temporal_expression"] = temporal.expression
            if let duration = temporal.durationSeconds { entities["duration_seconds"] = String(duration) }
            if let hour = temporal.hour, let minute = temporal.minute {
                entities["hour"] = String(format: "%02d", hour)
                entities["minute"] = String(format: "%02d", minute)
            }
            if let dayPeriod = temporal.dayPeriod { entities["day_period"] = dayPeriod }
        }
        if let numeric = frame.numeric {
            entities["numeric_tokens"] = numeric.orderedTokens.joined(separator: "|")
            if let percentage = numeric.percentage { entities["percentage"] = NSDecimalNumber(decimal: percentage).stringValue }
        }
        if let reference = frame.contextReference { entities["context_reference"] = reference.rawValue }
        if !frame.entityAmbiguity.isEmpty { entities["clarification_options"] = frame.entityAmbiguity.joined(separator: "|") }
        if let compound = frame.compound {
            entities["compound_clause_count"] = String(compound.clauses.count)
            entities["compound_order"] = compound.isSequential ? "sequential" : "parallel"
        }

        // SOURCE controls the domain. “documents in Photos” is a Photos query;
        // the object alone must never redirect it to Files.
        if frame.source == .photos {
            entities["query"] = (frame.modifiers.contains("latest") || frame.modifiers.contains("penultimate") || frame.action.map { [.open, .show].contains($0) } == true) ? "recent" : semanticPhotoSubject(original)
            if frame.action == .open { entities["requested_action"] = "open" }
            if frame.action == .share { entities["requested_action"] = "share" }
            if frame.action == .recognize { entities["requested_action"] = "ocr" }
            return (.photoSearch, entities)
        }
        if frame.source == .files || frame.object == .file ||
            (frame.object == .document && frame.action.map { [.open, .choose].contains($0) } == true) {
            entities["query"] = frame.object == .file ? "file" : "document"
            return (.fileSearch, entities)
        }
        if frame.source == .camera, frame.action.map({ [.scan, .recognize].contains($0) }) == true {
            entities["capture_mode"] = frame.object == .code ? "code_scan" : "text_scan"
            if frame.object == .document {
                entities["input_source"] = "document_camera"
                if lexicalTokens(normalized).contains("pdf") { entities["output_format"] = "pdf" }
            }
            return (.cameraCapture, entities)
        }
        if frame.source == .documents, frame.action == .recognize {
            entities["capture_mode"] = "text_scan"
            entities["input_source"] = "document"
            return (.cameraCapture, entities)
        }
        if frame.source == .clipboard {
            if frame.action == .copy {
                entities["system_action"] = "clipboard"
            } else if frame.action == .open || frame.object == .url {
                entities["system_action"] = "clipboard_open_url"
            } else {
                entities["system_action"] = "clipboard_read"
            }
            return (.deviceAction, entities)
        }

        // Settings are modeled as an object/target family before generic
        // open/show actions are considered. Public iOS exposes this app's
        // settings page, but not arbitrary system-settings destinations.
        if frame.object == .settings {
            entities["settings_target"] = settingsTarget(in: normalized)
            return (.settings, entities)
        }
        if frame.object == .battery || frame.object == .storage {
            entities["system_action"] = frame.object == .battery ? "battery" : "storage"
            return (.deviceAction, entities)
        }

        if frame.object == .photo {
            if frame.action == .create {
                entities["capture_mode"] = "visible_camera"
                return (.cameraCapture, entities)
            }
            guard frame.action != nil || frame.modifiers.contains("latest") else { return (nil, entities) }
            let recentSelection = frame.modifiers.contains("latest") || frame.modifiers.contains("penultimate") || [.open, .show].contains(frame.action)
            entities["query"] = recentSelection ? "recent" : semanticPhotoSubject(original)
            if frame.action == .open { entities["requested_action"] = "open" }
            if frame.action == .share { entities["requested_action"] = "share" }
            if frame.action == .recognize { entities["requested_action"] = "ocr" }
            return (.photoSearch, entities)
        }

        if frame.object == .contact && frame.action.map({ [.search, .show, .query].contains($0) }) == true {
            guard let person = frame.person, !person.isEmpty else {
                return (.deviceAction, ["system_action": "unsupported_system_control"])
            }
            entities["contact"] = person
            return (.contactLookup, entities)
        }
        if frame.action == .call {
            if let person = frame.person, !person.isEmpty { entities["contact"] = person }
            if let service = frame.service { entities["call_service"] = service }
            return (.contactCall, entities)
        }
        if frame.action == .message {
            if let person = frame.person, !person.isEmpty { entities["recipient"] = person }
            if let service = frame.service { entities["message_service"] = service }
            return (.messageCompose, entities)
        }

        if frame.object == .weather || weatherQuestion(normalized) {
            if frame.modifiers.contains("current_location") || frame.contextReference == .currentLocation {
                entities["near_current_location"] = "true"
            }
            if let location = frame.location { entities["location"] = location }
            return (.weather, entities)
        }

        if frame.object == .calendar {
            // Record/add/set plus a declarative event with a concrete temporal role are creates.
            // Query/show/open remain reads, preventing noun-only cross-family theft.
            if frame.action == .create || frame.action == .record || frame.action == .set ||
                (frame.action == nil && frame.temporal != nil) {
                return (.calendarCreate, entities)
            }
            if frame.action == .update { return (.calendarUpdate, entities) }
            if frame.action == .delete { return (.calendarDelete, entities) }
            return (.calendarQuery, entities)
        }
        if frame.object == .reminder {
            if frame.action == .create || frame.action == .set { return (.reminderCreate, entities) }
            if frame.action == .delete { return (.reminderDelete, entities) }
            return (.reminderQuery, entities)
        }
        if frame.object == .timer || frame.object == .alarm {
            guard frame.action == .set || frame.action == .create else {
                // AlarmKit supports app-created alarms, but it is not a public
                // replacement for browsing the user's Clock alarm database.
                return (.deviceAction, ["system_action": "unsupported_system_control"])
            }
            entities["system_action"] = frame.object == .timer ? "timer" : "alarm"
            return (.deviceAction, entities)
        }

        if frame.action == .scan || frame.action == .recognize || (frame.action == .create && frame.object == .document) {
            if frame.object == .code {
                entities["capture_mode"] = "code_scan"
                return (.cameraCapture, entities)
            }
            if frame.object == .document || frame.object == .text {
                entities["capture_mode"] = "text_scan"
                if frame.object == .document {
                    entities["input_source"] = "document_camera"
                    if lexicalTokens(normalized).contains("pdf") { entities["output_format"] = "pdf" }
                }
                return (.cameraCapture, entities)
            }
        }

        if frame.object == .travelTime {
            entities["system_action"] = "travel_time"
            if let location = frame.location { entities["destination"] = location }
            return (.deviceAction, entities)
        }

        if frame.object == .audio && frame.action.map({ [.record, .set, .create].contains($0) }) == true {
            entities["recorder_action"] = "start"
            return (.audioRecord, entities)
        }

        if frame.object == .media, let app = frame.app {
            entities["app"] = app
            entities["query"] = mediaSubject(original, app: app)
            return (.mediaSearch, entities)
        }
        if frame.action == .open, let app = frame.app {
            return (.open, ["app": app])
        }

        if frame.action == .navigate {
            if let location = frame.location { entities["destination"] = location }
            return (frame.location == nil ? .routeSearch : .navigation, entities)
        }
        return (nil, entities)
    }

    private func lexicalTokens(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    private func action(in tokens: [String]) -> CanonicalSemanticFrame.Action? {
        let visualObject = tokens.contains { token in
            ["фото", "світлин", "знім", "сним", "photo", "image", "picture"].contains { token.hasPrefix($0) }
        }
        let textualContent = tokens.contains { token in
            ["напис", "текст", "слов", "надпис", "written", "text", "word", "read"].contains { token.hasPrefix($0) }
        }
        if visualObject && textualContent { return .recognize }
        let messageObject = tokens.contains { token in
            ["повідом", "сообщ", "message", "sms"].contains { token.hasPrefix($0) }
        }
        let sendVerb = tokens.contains { token in
            ["напиш", "надішл", "відправ", "отправ", "message", "send"].contains { token.hasPrefix($0) }
        }
        if messageObject && sendVerb { return .message }
        // Interrogatives are closed lexical tokens. Prefix matching `що`
        // would incorrectly classify role-bearing words such as `щодо` as a
        // query and turn a declarative event payload into a calendar read.
        let interrogatives: Set<String> = [
            "чи", "що", "який", "яка", "яке", "які", "котрий", "котра",
            "есть", "какой", "какая", "какие", "which", "what"
        ]
        if !interrogatives.isDisjoint(with: tokens) { return .query }

        let families: [(CanonicalSemanticFrame.Action, [String])] = [
            (.delete, ["видал", "скас", "удал", "отмен", "delete", "remove", "cancel"]),
            (.update, ["перенес", "перенос", "змін", "измени", "move", "reschedul", "update"]),
            (.choose, ["вибер", "обер", "выбер", "select", "choose"]),
            (.share, ["поділ", "подел", "надішл", "відправ", "отправ", "share", "send"]),
            (.recognize, ["розпіз", "распозн", "прочит", "recogn", "read"]),
            (.copy, ["скопію", "копію", "скопир", "copy"]),
            (.scan, ["скан", "оцифр", "digitiz"]),
            (.record, ["аудіозап", "аудиозап", "запис", "розпоч", "начн", "record"]),
            (.call, ["подзвон", "зателефон", "набер", "позвон", "call", "dial"]),
            (.message, ["напиш", "повідом", "сообщ", "message"]),
            (.navigate, ["маршрут", "вед", "проклад", "їхат", "ехать", "navigat", "route"]),
            (.create, ["створ", "дод", "заплан", "созд", "добав", "create", "add", "schedule"]),
            (.set, ["постав", "встанов", "установ", "запуст", "увімк", "включ", "розбуд", "start", "activate", "set"]),
            (.open, ["відкр", "откр", "open", "перейд"]),
            (.search, ["знайд", "пошук", "найд", "search", "find"]),
            (.show, ["покаж", "show", "display"])
        ]
        if let leading = tokens.first,
           let explicit = families.first(where: { _, roots in roots.contains { actionToken(leading, matches: $0) } }) {
            return explicit.0
        }
        return families.first { _, roots in tokens.contains { token in roots.contains { actionToken(token, matches: $0) } } }?.0
    }

    private func actionToken(_ token: String, matches root: String) -> Bool {
        if token.hasPrefix(root) { return true }
        let prefixes = ["пере", "про", "при", "від", "вы", "ви", "за", "по"]
        return prefixes.contains { prefix in
            token.hasPrefix(prefix) && token.dropFirst(prefix.count).hasPrefix(root)
        }
    }

    private func object(in tokens: [String]) -> CanonicalSemanticFrame.Object? {
        let families: [(CanonicalSemanticFrame.Object, [String])] = [
            (.contact, ["контакт"]),
            (.audio, ["аудіозап", "аудиозап", "голосов", "голосов", "звукозап", "voice", "recording"]),
            (.reminder, ["нагадув", "напомин", "reminder"]),
            (.calendar, ["календар", "поді", "зустр", "событ", "event", "appointment"]),
            (.timer, ["таймер", "timer"]),
            (.alarm, ["будильник", "розбуд", "alarm", "wake"]),
            (.settings, ["налаштуван", "настрой", "параметр", "settings", "preferences", "einstellungen", "réglages"]),
            (.battery, ["батаре", "акумулятор", "battery"]),
            (.storage, ["сховищ", "простор", "памят", "storage", "diskspace"]),
            (.travelTime, ["триваліст", "час-дорозі", "traveltime", "duration"]),
            (.code, ["qr", "barcode", "штрихкод", "код"]),
            (.text, ["текст", "text"]),
            (.weather, ["погод", "температур", "дощ", "дожд", "холод", "спек", "жарк", "weather", "rain", "cold", "hot"]),
            (.photo, ["фото", "світлин", "знім", "сним", "photo", "image", "picture"]),
            (.file, ["файл", "file"]),
            (.document, ["документ", "document", "pdf"]),
            (.note, ["нотат", "замет", "note"]),
            (.url, ["url", "посилан", "ссылк", "link", "вебадрес", "webaddress"]),
            (.media, ["плейлист", "playlist", "добір", "подбор", "selection", "пісн", "песн", "song", "трек", "track"]),
            (.app, ["програм", "застос", "прилож", "app"])
        ]
        return families.first { _, roots in tokens.contains { token in roots.contains { token.hasPrefix($0) } } }?.0
    }

    private func isApplicationSettingsRequest(tokens: [String], normalized: String) -> Bool {
        let permissionRole = tokens.contains { token in
            ["дозвол", "доступ", "разреш", "permission", "access", "berechtigung", "autorisation"].contains { token.hasPrefix($0) }
        }
        return permissionRole && settingsTarget(in: normalized) == "application"
    }

    private func settingsTarget(in text: String) -> String {
        let applicationReferences = [
            "universalassistant", "universal assistant", "цього застосунку",
            "цьому застосунку", "цього додатку", "цьому додатку",
            "этого приложения", "этому приложению", "this app", "the app"
        ]
        return applicationReferences.contains(where: text.contains) ? "application" : "system"
    }

    private func source(in tokens: [String]) -> CanonicalSemanticFrame.Source? {
        if tokens.contains(where: { ["photos", "photolibrary"].contains($0) }) { return .photos }
        if tokens.contains(where: { ["файлів", "файлах", "files", "icloud", "drive"].contains($0) }) { return .files }
        if tokens.contains(where: { token in ["буфер", "clipboard"].contains(where: token.hasPrefix) }) { return .clipboard }
        if tokens.contains(where: { token in ["камер", "camera"].contains(where: token.hasPrefix) }) { return .camera }
        return nil
    }

    private func service(in tokens: [String]) -> ScopedEntityResolution<MessengerKind> {
        let domain = MessengerKind.allCases.map { kind in
            ScopedEntityCandidate(value: kind, displayName: kind.rawValue, aliases: [kind.rawValue])
        }
        let resolver = ContextScopedEntityResolver(candidates: domain)
        var ambiguity: Set<String> = []
        for token in tokens {
            switch resolver.resolve(token) {
            case let .resolved(value): return .resolved(value)
            case let .ambiguous(values): ambiguity.formUnion(values)
            case .unresolved: continue
            }
        }
        return ambiguity.isEmpty ? .unresolved : .ambiguous(ambiguity.sorted())
    }

    private func application(in tokens: [String]) -> String? {
        if tokens.contains("spotify") { return "Spotify" }
        if tokens.contains("youtube") { return "YouTube" }
        if tokens.contains("whatsapp") { return "WhatsApp" }
        if tokens.contains("telegram") { return "Telegram" }
        if tokens.contains("диктофон") || (tokens.contains("voice") && tokens.contains("memos")) { return "Voice Memos" }
        if tokens.contains("apple") && tokens.contains("music") { return "Apple Music" }
        return nil
    }

    private func modifiers(in tokens: [String]) -> Set<String> {
        var output: Set<String> = []
        if tokens.contains(where: { token in ["остан", "найнов", "найсвіж", "щойно", "послед", "latest", "newest", "recent"].contains(where: token.hasPrefix) }) {
            output.insert("latest")
        }
        if tokens.contains(where: { token in ["передостан", "предпослед", "penultimate"].contains(where: token.hasPrefix) }) {
            output.remove("latest")
            output.insert("penultimate")
        }
        if tokens.contains(where: { ["тут", "поруч", "зараз", "моє", "моему", "current", "here"].contains($0) }) {
            output.insert("current_location")
        }
        return output
    }

    private func temporalRole(in original: String, normalized: String) -> CanonicalSemanticFrame.TemporalRole? {
        let signals = ["сьогодні", "завтра", "післязавтра", "вчора", "через", "сегодня", "послезавтра", "вчера", "today", "tomorrow", "tonight", "yesterday", "in "]
        let timePattern = #"\b(?:[01]?\d|2[0-3])[:.]([0-5]\d)\b"#
        let durationPattern = #"\b([0-9]+(?:[.,][0-9]+)?)\s*(секунд\p{L}*|сек|seconds?|secs?|хвилин\p{L}*|хв|минут\p{L}*|мин|minutes?|mins?|годин\p{L}*|час\p{L}*|hours?|hrs?)\b"#
        guard signals.contains(where: normalized.contains)
                || normalized.range(of: timePattern, options: .regularExpression) != nil
                || normalized.range(of: durationPattern, options: .regularExpression) != nil else { return nil }
        var durationSeconds: Int?
        if let range = normalized.range(of: durationPattern, options: [.regularExpression, .caseInsensitive]) {
            let match = String(normalized[range])
            let parts = match.split(whereSeparator: { !$0.isNumber && $0 != "." && $0 != "," })
            if let number = parts.first.flatMap({ Double($0.replacingOccurrences(of: ",", with: ".")) }) {
                let multiplier: Double = match.contains("сек") || match.contains("sec") ? 1 : (match.contains("год") || match.contains("час") || match.contains("hour") || match.contains("hr") ? 3_600 : 60)
                durationSeconds = Int((number * multiplier).rounded())
            }
        }
        let clock = explicitClock(in: normalized)
        let dayPeriod: String? = if ["після обіду", "по обіді", "пополудні", "после обеда", "afternoon"].contains(where: normalized.contains) {
            "afternoon"
        } else if ["увечері", "вечором", "вечером", "evening"].contains(where: normalized.contains) {
            "evening"
        } else if ["вранці", "зранку", "утром", "morning"].contains(where: normalized.contains) {
            "morning"
        } else { nil }
        return .init(
            expression: original.trimmingCharacters(in: .whitespacesAndNewlines),
            durationSeconds: durationSeconds,
            hour: clock?.hour,
            minute: clock?.minute,
            dayPeriod: dayPeriod
        )
    }

    private func explicitClock(in text: String) -> (hour: Int, minute: Int)? {
        let pattern = #"(?<!\d)(?:о|об|в|at|um|a)?\s*([01]?\d|2[0-3])[:.]([0-5]\d)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let hourRange = Range(match.range(at: 1), in: text),
              let minuteRange = Range(match.range(at: 2), in: text),
              let hour = Int(text[hourRange]), let minute = Int(text[minuteRange]) else { return nil }
        return (hour, minute)
    }

    private func numericRole(in normalized: String) -> CanonicalSemanticFrame.NumericRole? {
        let range = NSRange(normalized.startIndex..., in: normalized)
        let values = Self.numericRegex.matches(in: normalized, range: range).compactMap { match -> String? in
            guard let valueRange = Range(match.range, in: normalized) else { return nil }
            return String(normalized[valueRange]).replacingOccurrences(of: ",", with: ".")
        }
        guard !values.isEmpty else { return nil }
        var percentage: Decimal?
        if let match = Self.percentageRegex.firstMatch(in: normalized, range: range), match.numberOfRanges > 1,
           let valueRange = Range(match.range(at: 1), in: normalized) {
            let value = String(normalized[valueRange]).replacingOccurrences(of: ",", with: ".")
            percentage = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
        }
        return .init(orderedTokens: values, percentage: percentage)
    }

    private func contextReference(in normalized: String) -> CanonicalSemanticFrame.ContextReference? {
        let tokens = lexicalTokens(normalized)
        let hasPhoto = tokens.contains { token in
            ["фото", "світлин", "знім", "сним", "photo", "image", "picture"].contains { token.hasPrefix($0) }
        }
        let hasDemonstrative = tokens.contains { token in
            ["цій", "цьому", "цього", "цією", "этой", "этом", "this", "that"].contains(token)
        }
        if hasPhoto && hasDemonstrative { return .sharedContent }
        if normalized.contains("по дорозі") || normalized.contains("по пути") || normalized.contains("along the route") { return .activeRoute }
        if normalized.contains("де я") || normalized.contains("где я") || normalized.contains("where i am") || normalized.contains("моє місцезнаходження") { return .currentLocation }
        if normalized.contains("останній результат") || normalized.contains("последний результат") || normalized.contains("last result") { return .previousResult }
        if normalized.contains("цій фотографії") || normalized.contains("shared image") || normalized.contains("цим посиланням") { return .sharedContent }
        if normalized.contains("цей результат") || normalized.contains("обраний") || normalized.contains("selected result") { return .selectedResult }
        return nil
    }

    private func compoundRole(in original: String, normalized: String) -> CanonicalSemanticFrame.CompoundRole? {
        let clauses = CompoundCommandClauses.split(original)
        guard clauses.count > 1 else { return nil }
        let sequential = ["потім", "затем", "then", "danach", "puis"].contains(where: normalized.contains)
        return .init(clauses: clauses, isSequential: sequential)
    }

    private func trailingEntity(_ original: String, afterActionFamilies: [[String]], stoppingAt stops: [String]) -> String? {
        let folded = original.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let allRoots = afterActionFamilies.flatMap { $0 }
        guard let tokenRange = folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).first(where: { token in
            allRoots.contains { token.hasPrefix($0) }
        }).flatMap({ folded.range(of: String($0)) }) else { return nil }
        var tail = String(original[tokenRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        for stop in stops {
            if let range = tail.range(of: stop, options: [.caseInsensitive, .diacriticInsensitive]) {
                tail = String(tail[..<range.lowerBound])
            }
        }
        tail = tail.replacingOccurrences(of: #"^(?:мені|мне|будь ласка|please|чи є в мене)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
        tail = tail.replacingOccurrences(of: #"^(?:контакт|повідомлення|сообщение|message)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
        return tail.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func locationPhrase(in original: String) -> String? {
        let markers = [" до ", " у ", " в ", " біля ", " поруч із ", " near ", " to "]
        return markers.compactMap { marker -> String? in
            guard let range = original.range(of: marker, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
            let value = original[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            return value.isEmpty ? nil : value
        }.first
    }

    private func navigationDestination(in original: String) -> String? {
        let patterns = [
            #"^\s*(?:веди|проведи|navigate|take me|приведи)\s+(?:мене\s+|меня\s+)?(.+?)\s*$"#,
            #"^\s*(?:їхати|ехать|go)\s+(.+?)\s*$"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: original, range: NSRange(original.startIndex..., in: original)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: original) else { continue }
            let value = original[range].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if !value.isEmpty { return value }
        }
        return nil
    }

    private func weatherQuestion(_ text: String) -> Bool {
        ["температур", "холодн", "спекотн", "жарк", "чи буде дощ", "будет дождь", "weather", "rain", "cold", "hot"].contains(where: text.contains)
    }

    private func semanticPhotoSubject(_ original: String) -> String {
        original.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func mediaSubject(_ original: String, app: String) -> String {
        original.replacingOccurrences(of: app, with: "", options: [.caseInsensitive, .diacriticInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func confidence(_ frame: CanonicalSemanticFrame) -> Double {
        let filled = [frame.action != nil, frame.object != nil, frame.source != nil, frame.person != nil, frame.service != nil, frame.app != nil, frame.location != nil, frame.temporal != nil, frame.numeric != nil, frame.contextReference != nil, frame.compound != nil].filter { $0 }.count
        return min(1, 0.55 + Double(filled) * 0.08)
    }
}
