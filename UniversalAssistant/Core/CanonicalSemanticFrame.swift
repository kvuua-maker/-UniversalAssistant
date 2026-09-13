import Foundation

/// A role-preserving interpretation produced before capability selection.
/// It intentionally describes the whole command instead of treating any one
/// noun (for example “document”) as an intent.
struct CanonicalSemanticFrame: Equatable, Sendable {
    enum Action: String, Sendable { case open, choose, search, show, create, update, delete, copy, call, message, scan, recognize, share, navigate, query, set, record, enable, disable }
    enum Object: String, Sendable { case file, photo, document, contact, calendar, reminder, timer, alarm, app, settings, battery, storage, flashlight, brightness, volume, powerMode, networkControl, phoneHistory, deviceLocator, url, place, restaurant, reservation, weather, travelTime, text, code, note, audio, audioRoute, media }
    enum Source: String, Sendable { case files, photos, documents, clipboard, camera, calendar, reminders }
    enum ContextReference: String, Sendable { case currentLocation, activeRoute, selectedResult, sharedContent, previousResult }

    struct TemporalRole: Equatable, Sendable {
        let expression: String
        let kind: CanonicalTemporalAnalyzer.Kind
        let durationSeconds: Int?
        let relativeIntervalSeconds: Int?
        let relativeDayOffset: Int?
        let weekday: Int?
        let calendarYear: Int?
        let calendarMonth: Int?
        let calendarDay: Int?
        let hour: Int?
        let minute: Int?
        let dayPeriod: String?
        let confidence: Double
        let evidence: Set<String>
        let requiresClarification: Bool
    }
    struct NumericRole: Equatable, Sendable { let orderedTokens: [String]; let percentage: Decimal? }
    struct CompoundRole: Equatable, Sendable { let clauses: [String]; let isSequential: Bool }

    var action: Action?
    var object: Object?
    var source: Source?
    var service: String?
    var entityAmbiguity: [String] = []
    var person: String?
    var messageBody: String?
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

    func analyze(
        original: String,
        normalized: String,
        morphologyForms: [Set<String>] = []
    ) -> CanonicalSemanticFrameResult {
        let lexical = lexicalTokens(normalized)
        let lexicalSet = Set(lexical)
        let evidence = morphologyForms.flatMap { $0 }.filter { !lexicalSet.contains($0) }.sorted()
        let tokens = lexical + evidence
        var frame = CanonicalSemanticFrame()
        if isLeadingReminderCreation(in: tokens) {
            // The remainder is reminder payload. Words such as “reservation”
            // or “copy” inside that payload cannot steal ACTION/OBJECT roles.
            frame.action = .create
            frame.object = .reminder
        } else {
            frame.action = action(in: tokens)
            frame.object = object(in: tokens)
        }
        let hasConversationObject = tokens.contains { token in
            ["чат", "переписк", "розмов", "диалог", "conversation", "chat", "thread"].contains {
                token.hasPrefix($0)
            }
        }
        if hasConversationObject, frame.action == .open || frame.action == .show {
            frame.action = .message
        }
        if frame.object == nil, isContactDetailRequest(tokens: tokens, action: frame.action) {
            frame.object = .contact
        }
        if frame.object == nil, isReservationMutation(in: tokens) {
            frame.object = .reservation
            if frame.action == nil { frame.action = .create }
        }
        let hasEventNoun = tokens.contains(where: { token in
               ["поді", "событ", "event", "appointment"].contains { token.hasPrefix($0) }
           })
        let mutatesCalendarEvent = frame.action.map({ [.create, .record, .set, .update, .delete].contains($0) }) == true
        let queriesPersonalCalendar = frame.action.map({ [.open, .show, .search, .query].contains($0) }) == true &&
            tokens.contains(where: { token in
                ["мо", "мій", "моя", "заплан", "календар", "my", "scheduled", "calendar"].contains {
                    token.hasPrefix($0)
                }
            })
        if hasEventNoun, mutatesCalendarEvent || (frame.object == nil && queriesPersonalCalendar) {
            // An event noun becomes personal Calendar state only together with
            // a mutation or explicit personal-calendar evidence. Public event
            // discovery remains a provider domain instead of being stolen by EventKit.
            frame.object = .calendar
        }
        if isApplicationSettingsRequest(tokens: tokens, normalized: normalized) {
            frame.object = .settings
        }
        let hasVisualObject = tokens.contains { token in
            ["фото", "світлин", "знім", "сним", "відео", "скріншот", "photo", "image", "picture", "video", "screenshot"].contains { token.hasPrefix($0) }
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
        // A verified communication channel is structural evidence that a leading
        // send/share verb describes MESSAGE, not generic sharing. Keep recovery
        // scoped to communication actions so unrelated text cannot manufacture a
        // messenger entity.
        let communicationAction = frame.action == .call || frame.action == .message ||
            (frame.action == .share && tokens.first.map(isSendActionToken) == true)
        if communicationAction {
            let explicitServiceScope = tokens.contains { token in
                ["через", "via", "using", "service", "канал", "сервіс", "сервис"].contains(token)
            }
            switch service(in: tokens) {
            case let .resolved(service):
                frame.service = service
                if frame.action == .share { frame.action = .message }
            case let .ambiguous(values) where explicitServiceScope:
                frame.entityAmbiguity = values
            case .ambiguous:
                // A fuzzy collision produced by the action or recipient is not
                // evidence that the user selected a messenger. Normal calls and
                // messages stay on their default public Apple channel.
                break
            case .unresolved: break
            }
        }
        frame.app = application(in: tokens)
        frame.modifiers = modifiers(in: tokens)

        if frame.action == .message, let roles = CanonicalMessageRoleAnalyzer.analyze(original, explicitService: frame.service) {
            frame.person = roles.recipient
            frame.messageBody = roles.body
        } else if frame.object == .contact || frame.action == .call {
            let contactSubject = trailingEntity(
                original,
                afterActionFamilies: [
                    ["контакт", "contact"], ["подзвон", "зателефон", "набер", "позвон", "call", "dial"],
                    ["покаж", "знайд", "відобраз", "show", "find", "display"]
                ],
                stoppingAt: [" через ", " via ", " using "]
            )
            frame.person = contactDetailPerson(contactSubject, excludingService: frame.service)
        }
        frame.location = locationPhrase(in: original)
        if frame.action == .navigate, frame.location == nil {
            frame.location = navigationDestination(in: original)
        }
        frame.temporal = temporalRole(in: original, normalized: normalized, object: frame.object)
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
            entities["temporal_kind"] = temporal.kind.rawValue
            entities["temporal_confidence"] = String(format: "%.3f", temporal.confidence)
            entities["temporal_evidence"] = temporal.evidence.sorted().joined(separator: "|")
            if let duration = temporal.durationSeconds { entities["duration_seconds"] = String(duration) }
            if let interval = temporal.relativeIntervalSeconds { entities["relative_interval_seconds"] = String(interval) }
            if let offset = temporal.relativeDayOffset { entities["relative_day_offset"] = String(offset) }
            if let weekday = temporal.weekday { entities["weekday"] = String(weekday) }
            if let year = temporal.calendarYear { entities["calendar_year"] = String(year) }
            if let month = temporal.calendarMonth { entities["calendar_month"] = String(month) }
            if let day = temporal.calendarDay { entities["calendar_day"] = String(day) }
            if let hour = temporal.hour, let minute = temporal.minute {
                entities["hour"] = String(format: "%02d", hour)
                entities["minute"] = String(format: "%02d", minute)
            }
            if let dayPeriod = temporal.dayPeriod { entities["day_period"] = dayPeriod }
            if temporal.requiresClarification { entities["temporal_requires_clarification"] = "true" }
        }
        if let numeric = frame.numeric {
            entities["numeric_tokens"] = numeric.orderedTokens.joined(separator: "|")
            if let percentage = numeric.percentage { entities["percentage"] = NSDecimalNumber(decimal: percentage).stringValue }
        }
        if let reference = frame.contextReference { entities["context_reference"] = reference.rawValue }
        if !frame.entityAmbiguity.isEmpty {
            entities["clarification_options"] = frame.entityAmbiguity.joined(separator: "|")
            entities["clarification_role"] = "service_channel"
        }
        if let compound = frame.compound {
            entities["compound_clause_count"] = String(compound.clauses.count)
            entities["compound_order"] = compound.isSequential ? "sequential" : "parallel"
        }

        if [.previousResult, .selectedResult].contains(frame.contextReference) {
            if frame.action == .copy { entities["system_action"] = "clipboard_copy_context"; return (.deviceAction, entities) }
            if frame.action == .share { entities["system_action"] = "share_context"; return (.deviceAction, entities) }
        }

        if frame.contextReference == .activeRoute,
           frame.action == nil || [.search, .show, .query].contains(frame.action!) {
            entities["query"] = original
            return (.routeAwareSearch, entities)
        }

        // SOURCE controls the domain. “documents in Photos” is a Photos query;
        // the object alone must never redirect it to Files.
        if frame.source == .photos {
            entities.merge(photoQueryEntities(frame: frame, original: original)) { _, new in new }
            if frame.action == .open { entities["requested_action"] = "open" }
            if frame.action == .share { entities["requested_action"] = "share" }
            if frame.action == .recognize { entities["requested_action"] = "ocr" }
            return (.photoSearch, entities)
        }
        if frame.source == .files || frame.object == .file ||
            (frame.object == .document && frame.action.map { [.open, .choose, .search, .show, .query].contains($0) } == true) {
            let asksForPDF = lexicalTokens(normalized).contains("pdf")
            entities["query"] = asksForPDF ? "pdf" : (frame.object == .file ? "file" : "document")
            if asksForPDF { entities["file_type"] = "public.pdf" }
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
        if frame.source == .camera, frame.action.map({ [.open, .create, .set, .record].contains($0) }) == true {
            entities["capture_mode"] = "visible_camera"
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
        if frame.object == .flashlight {
            entities["system_action"] = "flashlight"
            entities["enabled"] = frame.action == .disable ? "false" : "true"
            return (.deviceAction, entities)
        }
        if frame.object == .audioRoute {
            entities["system_action"] = "audio_route_picker"
            return (.deviceAction, entities)
        }
        if let object = frame.object, [.brightness, .volume, .powerMode, .networkControl, .phoneHistory, .deviceLocator].contains(object) {
            entities["system_action"] = "unsupported_system_control"
            entities["system_target"] = object.rawValue
            return (.deviceAction, entities)
        }

        // Notes are a distinct semantic object. Create uses the public share boundary; query terminates locally.
        if frame.object == .note {
            return (frame.action == .create || frame.action == .record ? .noteCreate : .noteQuery, entities)
        }

        if frame.object == .photo {
            if frame.action == .create {
                entities["capture_mode"] = "visible_camera"
                return (.cameraCapture, entities)
            }
            guard frame.action != nil || frame.modifiers.contains("latest") else { return (nil, entities) }
            entities.merge(photoQueryEntities(frame: frame, original: original)) { _, new in new }
            if frame.action == .open { entities["requested_action"] = "open" }
            if frame.action == .share { entities["requested_action"] = "share" }
            if frame.action == .recognize { entities["requested_action"] = "ocr" }
            return (.photoSearch, entities)
        }

        if frame.object == .contact && frame.action.map({ [.open, .search, .show, .query].contains($0) }) == true {
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
            if let body = frame.messageBody, !body.isEmpty { entities["message_body"] = body }
            return (.messageCompose, entities)
        }

        if frame.object == .restaurant || frame.object == .reservation {
            if let partySize = partySize(in: normalized) { entities["party_size"] = String(partySize) }
            entities["restaurant_query"] = restaurantSubject(original)
            if frame.modifiers.contains("current_location") { entities["near_current_location"] = "true" }
            switch frame.action {
            case .update:
                entities["reservation_operation"] = "modify"
                return (.reservation, entities)
            case .delete:
                // Cancellation remains the general canonical action. The typed
                // reservation operation lets the executor bind it to the
                // currently verified restaurant booking without redefining
                // every generic “cancel booking” command as discovery.
                entities["reservation_operation"] = "cancel"
                return (.cancel, entities)
            case .create, .set:
                entities["reservation_operation"] = "availability"
                entities["reservation_requested_mutation"] = "book"
                return (.reservation, entities)
            case .search, .show, .query:
                if frame.temporal != nil || entities["party_size"] != nil {
                    entities["reservation_operation"] = "availability"
                    return (.reservation, entities)
                }
                entities["query"] = entities["restaurant_query"]
                return (.placeSearch, entities)
            default:
                if frame.object == .restaurant {
                    // A restaurant noun plus proximity is a Place search, not
                    // an underspecified table mutation.
                    entities["query"] = entities["restaurant_query"]
                    return (.placeSearch, entities)
                }
                entities["reservation_operation"] = "availability"
                return (.reservation, entities)
            }
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
            guard frame.action == .set || frame.action == .create || frame.action == .enable else {
                // AlarmKit supports app-created alarms, but it is not a public
                // replacement for browsing the user's Clock alarm database.
                return (.deviceAction, ["system_action": "unsupported_system_control"])
            }
            entities["system_action"] = frame.object == .timer ? "timer" : "alarm"
            return (.deviceAction, entities)
        }

        if frame.object == .document, let operation = pdfOperation(in: lexicalTokens(normalized)) {
            entities["pdf_operation"] = operation.rawValue
            if [.highlight, .redact].contains(operation), let marker = original.range(of: "текст", options: [.caseInsensitive]) {
                let value = original[marker.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                if !value.isEmpty { entities["pdf_text"] = value }
            }
            return (.fileSearch, entities)
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
            entities["recorder_action"] = recorderLifecycleAction(in: lexicalTokens(normalized))
            return (.audioRecord, entities)
        }

        if frame.object == .media, let app = frame.app {
            entities["app"] = app
            entities["query"] = mediaSubject(original, app: app)
            return (.mediaSearch, entities)
        }
        if let app = frame.app, frame.action.map({ [.open, .set, .enable].contains($0) }) == true {
            return (.open, ["app": app])
        }

        if frame.action == .navigate {
            if let location = frame.location { entities["destination"] = location }
            let transitMode = ["громадськ", "транспорт", "автобус", "метро", "трамва", "тролейбус", "обществен", "transit", "public transport"].contains(where: normalized.contains)
            let asksForRoute = ["як", "как", "how"].contains(where: lexicalTokens(normalized).contains)
            if transitMode { entities["travel_mode"] = "transit" }
            return (transitMode || asksForRoute ? .transportRoute : (frame.location == nil ? .routeSearch : .navigation), entities)
        }
        let routeEvidence = ["маршрут", "дорог", "шлях", "путь", "directions", "route", "path"]
            .contains(where: normalized.contains)
        if routeEvidence, frame.location != nil,
           frame.action.map({ [.search, .show, .query].contains($0) }) == true {
            entities["destination"] = frame.location
            return (.navigation, entities)
        }

        // Proximity is a structural location constraint. Once it is present,
        // an otherwise open-ended search/query describes a local Place rather
        // than a catalog product or general-web request. MapKit remains
        // authoritative for category interpretation and ranking.
        if frame.modifiers.contains("proximity"),
           frame.object == nil,
           frame.action == nil || [.search, .show, .query].contains(frame.action!) {
            entities["near_current_location"] = "true"
            entities["query"] = original
            return (.placeSearch, entities)
        }
        // A broad SHOW/QUERY frame is not itself authoritative enough to
        // suppress a more specific canonical family recognized by the shared
        // parser. Leave capability unresolved for canonical precedence.
        return (nil, entities)
    }

    private func lexicalTokens(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    private func action(in tokens: [String]) -> CanonicalSemanticFrame.Action? {
        let visualObject = tokens.contains { token in
            ["фото", "світлин", "знім", "сним", "відео", "скріншот", "photo", "image", "picture", "video", "screenshot"].contains { token.hasPrefix($0) }
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
        let families: [(CanonicalSemanticFrame.Action, [String])] = [
            (.query, ["перевір", "дізнай", "розкаж", "уточн", "check", "tell", "explain", "query"]),
            (.disable, ["вимк", "выключ", "disable", "turnoff"]),
            (.enable, ["увімк", "включ", "enable", "turnon"]),
            (.delete, ["видал", "скас", "удал", "отмен", "delete", "remove", "cancel"]),
            (.update, ["перенес", "перенос", "змін", "измени", "move", "reschedul", "update"]),
            (.choose, ["вибер", "обер", "выбер", "перемк", "переключ", "switch", "select", "choose"]),
            (.share, ["поділ", "подел", "надішл", "відправ", "отправ", "share", "send"]),
            (.recognize, ["розпіз", "распозн", "прочит", "recogn", "read"]),
            (.copy, ["скопію", "копію", "скопир", "copy"]),
            (.scan, ["скан", "оцифр", "digitiz"]),
            (.record, ["аудіозап", "аудиозап", "запис", "розпоч", "начн", "record", "призуп", "припин", "пауз", "продовж", "віднов", "resume", "pause", "зупин", "заверш", "закінч", "останов", "fortsetz", "pausier", "stopp", "reprend", "arrêt"]),
            (.call, ["подзвон", "зателефон", "набер", "позвон", "call", "dial"]),
            (.message, ["напиш", "повідом", "сообщ", "message"]),
            (.navigate, ["маршрут", "шлях", "дорог", "путь", "вед", "проклад", "їхат", "ехать", "діст", "добрат", "reach", "navigat", "route", "path"]),
            (.create, ["створ", "дод", "заплан", "заброн", "резерв", "созд", "добав", "create", "add", "schedule", "book", "reserve"]),
            (.set, ["постав", "встанов", "установ", "запуст", "увімк", "включ", "розбуд", "start", "activate", "set"]),
            (.open, ["відкр", "откр", "open", "перейд"]),
            (.search, ["знайд", "пошук", "найд", "search", "find"]),
            (.show, ["покаж", "відобраз", "відображ", "show", "display", "render"])
        ]
        if let leading = tokens.first,
           let explicit = families.first(where: { _, roots in roots.contains { actionToken(leading, matches: $0) } }) {
            return explicit.0
        }
        let howInterrogatives: Set<String> = ["як", "как", "how"]
        let movementRoots = ["діст", "добрат", "доїхат", "доехать", "reach", "navigat", "route"]
        if !howInterrogatives.isDisjoint(with: tokens),
           tokens.contains(where: { token in movementRoots.contains { actionToken(token, matches: $0) } }) {
            return .navigate
        }
        // A leading imperative owns the ACTION role. Interrogatives in its
        // payload must not turn the command into a query for another family.
        let interrogatives: Set<String> = [
            "чи", "що", "який", "яка", "яке", "які", "котрий", "котра",
            "чому", "як", "есть", "какой", "какая", "какие", "почему", "как",
            "which", "what", "why", "how"
        ]
        if !interrogatives.isDisjoint(with: tokens) { return .query }
        return families.first { _, roots in tokens.contains { token in roots.contains { actionToken(token, matches: $0) } } }?.0
    }

    private func isLeadingReminderCreation(in tokens: [String]) -> Bool {
        guard let leading = tokens.first else { return false }
        let roots = [
            "нагада", "напомн", "remind", "erinner", "rappel"
        ]
        return roots.contains { actionToken(leading, matches: $0) }
    }

    private func pdfOperation(in tokens: [String]) -> PDFWorkflowOperation? {
        let families: [(PDFWorkflowOperation, [String])] = [
            (.merge, ["обєдн", "зєдн", "злит", "merge", "combine"]),
            (.split, ["розділ", "split", "separate"]),
            (.rotate, ["поверн", "rotate"]),
            (.compress, ["стисн", "compress"]),
            (.highlight, ["виділ", "highlight"]),
            (.redact, ["заретуш", "редаг", "redact"]),
            (.read, ["прочит", "відкр", "read", "open"])
        ]
        return families.first { _, roots in tokens.contains { token in roots.contains { token.hasPrefix($0) } } }?.0
    }

    private func actionToken(_ token: String, matches root: String) -> Bool {
        if token.hasPrefix(root) { return true }
        let prefixes = ["пере", "про", "при", "від", "вы", "ви", "за", "по"]
        return prefixes.contains { prefix in
            token.hasPrefix(prefix) && token.dropFirst(prefix.count).hasPrefix(root)
        }
    }

    private func isSendActionToken(_ token: String) -> Bool {
        ["надішл", "відправ", "отправ", "send", "schick", "envoi"].contains { actionToken(token, matches: $0) }
    }

    private func recorderLifecycleAction(in tokens: [String]) -> String {
        let roots: [(String, [String])] = [
            ("pause", ["призуп", "припин", "пауз", "pause", "pausier"]),
            ("resume", ["продовж", "віднов", "resume", "fortsetz", "reprend"]),
            ("stop", ["зупин", "заверш", "закінч", "останов", "stop", "stopp", "arrêt"])
        ]
        return roots.first { _, candidates in
            tokens.contains { token in candidates.contains { actionToken(token, matches: $0) } }
        }?.0 ?? "start"
    }

    private func object(in tokens: [String]) -> CanonicalSemanticFrame.Object? {
        let hasAvailableCapacityModifier = tokens.contains { token in
            ["вільн", "свободн", "доступн", "залиш", "остат", "зайнят", "використ", "free", "available", "remaining", "occupied", "used", "total"].contains {
                token.hasPrefix($0)
            }
        }
        let hasStorageMeasure = tokens.contains { token in
            ["місц", "мест", "простір", "простор", "простран", "сховищ", "памят", "space", "storage", "capacity", "disk"].contains {
                token.hasPrefix($0)
            }
        }
        if hasAvailableCapacityModifier && hasStorageMeasure { return .storage }
        let hasBatteryNoun = tokens.contains { token in
            token.hasPrefix("батаре") || token == "battery" ||
                ((token.hasPrefix("акумулятор") || token.hasPrefix("аккумулятор")) &&
                 !token.hasPrefix("акумуляторн") && !token.hasPrefix("аккумуляторн"))
        }
        if hasBatteryNoun { return .battery }
        let audioQualifiers = ["аудіо", "аудио", "звук", "sound", "audio"]
        let routeTargets = [
            "аудіових", "аудиовых", "soundoutput", "audiooutput", "airplay",
            "колонк", "динамік", "динамик", "speaker"
        ]
        let deviceTargets = ["пристр", "устрой", "device", "output", "route", "вихід", "выход"]
        let hasAudioQualifier = tokens.contains { token in audioQualifiers.contains { token.hasPrefix($0) } }
        let hasRouteTarget = tokens.contains { token in routeTargets.contains { token.hasPrefix($0) } }
        let hasDeviceTarget = tokens.contains { token in deviceTargets.contains { token.hasPrefix($0) } }
        let hasMergedAudioDevice = tokens.contains { token in
            audioQualifiers.contains(where: token.hasPrefix) &&
                deviceTargets.contains { target in token.dropFirst().contains(target) }
        }
        if hasRouteTarget || hasMergedAudioDevice || (hasAudioQualifier && hasDeviceTarget) {
            return .audioRoute
        }
        let families: [(CanonicalSemanticFrame.Object, [String])] = [
            (.contact, ["контакт"]),
            (.reservation, ["бронюван", "резервац", "reservation", "booking"]),
            (.restaurant, ["ресторан", "restaurant", "столик", "table"]),
            (.audio, ["аудіозап", "аудиозап", "голосов", "звуков", "звукозап", "voice", "recording"]),
            (.reminder, ["нагадув", "напомин", "reminder"]),
            (.calendar, ["календар", "зустр"]),
            (.timer, ["таймер", "timer"]),
            (.alarm, ["будильник", "розбуд", "alarm", "wake"]),
            (.settings, ["налаштуван", "настрой", "параметр", "settings", "preferences", "einstellungen", "réglages"]),
            (.flashlight, ["ліхтар", "фонар", "flashlight", "torch"]),
            (.brightness, ["яскрав", "яркост", "brightness"]),
            (.volume, ["гучніст", "громкост", "volume"]),
            (.powerMode, ["енергозбереж", "энергосбереж", "lowpower"]),
            (.networkControl, ["wifi", "wi-fi", "bluetooth"]),
            (.phoneHistory, ["пропущен", "missedcall", "callhistory"]),
            (.deviceLocator, ["локатор", "findmy"]),
            (.travelTime, ["трив", "час-дорозі", "traveltime", "duration"]),
            (.code, ["qr", "barcode", "штрихкод", "код"]),
            (.text, ["текст", "text"]),
            (.weather, ["погод", "температур", "дощ", "дожд", "холод", "спек", "жарк", "вітр", "ветер", "прогноз", "weather", "rain", "cold", "hot", "wind", "forecast"]),
            (.photo, ["фото", "світлин", "знім", "сним", "відео", "скріншот", "photo", "image", "picture", "video", "screenshot"]),
            (.file, ["файл", "папк", "тека", "folder", "directory", "downloads"]),
            (.document, ["документ", "document", "pdf"]),
            (.note, ["нотат", "замет", "notiz", "note"]),
            (.url, ["url", "посилан", "ссылк", "link", "вебадрес", "webaddress"]),
            (.media, ["плейлист", "playlist", "добір", "подбор", "selection", "альбом", "album", "пісн", "песн", "song", "трек", "track", "композ", "composition"]),
            (.app, ["програм", "застос", "прилож", "app"])
        ]
        return families.first { _, roots in tokens.contains { token in roots.contains { token.hasPrefix($0) } } }?.0
    }

    private func isReservationMutation(in tokens: [String]) -> Bool {
        tokens.contains { token in
            ["заброн", "резерв", "book", "reserve"].contains { actionToken(token, matches: $0) }
        }
    }

    private func isContactDetailRequest(tokens: [String], action: CanonicalSemanticFrame.Action?) -> Bool {
        guard action.map({ [.open, .search, .show, .query].contains($0) }) == true else { return false }
        let explicitContact = tokens.contains { token in
            ["контакт", "contact"].contains { token.hasPrefix($0) }
        }
        let directContactDatum = tokens.contains { token in
            ["телефон", "email", "mail", "address", "phone"].contains {
                token.hasPrefix($0)
            }
        }
        let electronicMailDatum = tokens.contains { token in
            ["електрон", "электрон", "electronic"].contains { token.hasPrefix($0) }
        } && tokens.contains { token in
            ["пошт", "почт", "mail"].contains { token.hasPrefix($0) }
        }
        let isMailApplicationRequest = action == .open && tokens.contains { token in
            ["email", "mail", "пошт"].contains { token.hasPrefix($0) }
        }
        return (explicitContact || directContactDatum || electronicMailDatum) && !isMailApplicationRequest
    }

    private func partySize(in text: String) -> Int? {
        let patterns = [
            #"\b(?:на|для|for)\s+(\d{1,2})\s*(?:осіб\p{L}*|люд\p{L}*|персон\p{L}*|гост\p{L}*|people|persons?|guests?)\b"#,
            #"\b(\d{1,2})\s*(?:осіб\p{L}*|люд\p{L}*|персон\p{L}*|гост\p{L}*|people|persons?|guests?)\b"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text),
                  let value = Int(text[range]), (1...50).contains(value) else { continue }
            return value
        }
        return nil
    }

    private func restaurantSubject(_ original: String) -> String {
        let structuralRoots = [
            "знайд", "покаж", "заброн", "резерв", "перенес", "змін", "скас", "видал",
            "find", "show", "book", "reserve", "modify", "reschedul", "cancel",
            "ресторан", "столик", "бронюван", "резервац", "restaurant", "table", "booking",
            "сьогодні", "завтра", "післязавтра", "today", "tomorrow",
            "особ", "люд", "персон", "гост", "people", "person", "guest",
            "поруч", "поблиз", "неподал", "рядом", "nearby", "nearest", "closest"
        ]
        let structuralWords: Set<String> = ["на", "для", "о", "об", "at", "for", "у", "в", "біля", "near"]
        let values = lexicalTokens(original).filter { token in
            !structuralWords.contains(token) &&
                !token.allSatisfy(\.isNumber) &&
                !structuralRoots.contains(where: token.hasPrefix)
        }
        return values.isEmpty ? "restaurant" : values.joined(separator: " ")
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
        if tokens.contains(where: { token in ["photos", "photolibrary", "галер"].contains(where: token.hasPrefix) }) { return .photos }
        if tokens.contains(where: { token in token.hasPrefix("файл") || ["files", "icloud", "drive"].contains(token) }) { return .files }
        if tokens.contains(where: { token in ["буфер", "clipboard"].contains(where: token.hasPrefix) }) { return .clipboard }
        if tokens.contains(where: { token in ["камер", "camera"].contains(where: token.hasPrefix) }) { return .camera }
        return nil
    }

    private func service(in tokens: [String]) -> ScopedEntityResolution<String> {
        let hasElectronicModifier = tokens.contains { token in
            ["електрон", "электрон", "electronic"].contains { token.hasPrefix($0) }
        }
        let hasMailNoun = tokens.contains { token in
            ["лист", "пошт", "почт", "email", "mail"].contains { token.hasPrefix($0) }
        }
        let hasDirectMailName = tokens.contains { token in
            ["email", "mail", "пошт", "почт"].contains { token.hasPrefix($0) }
        }
        if hasDirectMailName || (hasElectronicModifier && hasMailNoun) {
            return .resolved("email")
        }
        // Without an explicit SERVICE/CHANNEL marker only an exact canonical
        // name is service evidence. Contextual fuzzy recovery happens later
        // inside the marked channel span, never over action/person tokens.
        let services = Set(MessengerKind.allCases.map(\.rawValue))
        for token in tokens {
            if services.contains(token) {
                return .resolved(token)
            }
        }
        return .unresolved
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
        if tokens.contains(where: { token in ["тут", "поруч", "поблиз", "неподал", "рядом", "nearby", "near", "найближ", "ближайш", "nearest", "closest", "зараз", "моє", "моему", "current", "here"].contains(where: token.hasPrefix) }) {
            output.insert("current_location")
        }
        if tokens.contains(where: { token in ["поруч", "поблиз", "неподал", "рядом", "nearby", "near", "найближ", "ближайш", "nearest", "closest"].contains(where: token.hasPrefix) }) {
            output.insert("proximity")
        }
        let universalQuantifiers: Set<String> = [
            "всі", "вся", "все", "всю", "весь", "всіх", "усі", "уся", "усе", "усю", "усіх",
            "всех", "all", "every"
        ]
        if tokens.contains(where: universalQuantifiers.contains) {
            output.insert("all")
        }
        return output
    }

    private func temporalRole(
        in original: String,
        normalized: String,
        object: CanonicalSemanticFrame.Object?
    ) -> CanonicalSemanticFrame.TemporalRole? {
        guard let result = CanonicalTemporalAnalyzer().analyze(normalized: normalized, object: object) else { return nil }
        return .init(
            expression: original.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: result.kind,
            durationSeconds: result.durationSeconds,
            relativeIntervalSeconds: result.relativeIntervalSeconds,
            relativeDayOffset: result.relativeDayOffset,
            weekday: result.weekday,
            calendarYear: result.calendarYear,
            calendarMonth: result.calendarMonth,
            calendarDay: result.calendarDay,
            hour: result.hour,
            minute: result.minute,
            dayPeriod: result.dayPeriod,
            confidence: result.confidence,
            evidence: result.evidence,
            requiresClarification: result.requiresClarification
        )
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
            ["фото", "світлин", "знім", "сним", "відео", "скріншот", "photo", "image", "picture", "video", "screenshot"].contains { token.hasPrefix($0) }
        }
        let hasDemonstrative = tokens.contains { token in
            ["цій", "цьому", "цього", "цією", "этой", "этом", "this", "that"].contains(token)
        }
        if hasPhoto && hasDemonstrative { return .sharedContent }
        let routeRelation = ["по дорозі", "по пути", "along the route", "вздовж", "уздовж", "along"].contains(where: normalized.contains)
        let routeNoun = ["маршрут", "дороз", "пут", "route"].contains(where: normalized.contains)
        if routeRelation && routeNoun { return .activeRoute }
        if normalized.contains("де я") || normalized.contains("где я") || normalized.contains("where i am") || normalized.contains("моє місцезнаходження") { return .currentLocation }
        let previousResultReference = tokens.contains { token in ["остан", "поперед", "послед", "previous", "last"].contains { root in token.hasPrefix(root) } } && tokens.contains { token in ["результ", "відповід", "ответ", "result", "answer"].contains { root in token.hasPrefix(root) } }
        if previousResultReference { return .previousResult }
        let explicitResultReference = tokens.contains { token in
            ["результ", "відповід", "ответ", "result", "answer"].contains { root in token.hasPrefix(root) }
        }
        if explicitResultReference { return .selectedResult }
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
        let locale = Locale(identifier: "uk_UA")
        let allRoots = afterActionFamilies
            .flatMap { $0 }
            .map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale) }
        guard let actionToken = original.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).first(where: { token in
            let foldedToken = String(token).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
            return allRoots.contains { foldedToken.hasPrefix($0) }
        }) else { return nil }

        // `String.Index` belongs to one concrete string. Unicode folding can change
        // grapheme boundaries, so an index found in a folded copy must never be used
        // to slice the original transcript. Keep the token as an original substring
        // and continue from its source-owned end index.
        var tail = String(original[actionToken.endIndex...]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        for stop in stops {
            if let range = tail.range(of: stop, options: [.caseInsensitive, .diacriticInsensitive]) {
                tail = String(tail[..<range.lowerBound])
            }
        }
        tail = tail.replacingOccurrences(of: #"^(?:мені|мне|будь ласка|please|чи є в мене)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
        tail = tail.replacingOccurrences(of: #"^(?:контакт|повідомлення|сообщение|message)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
        return tail.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
    private func communicationPerson(_ value: String?, excludingService service: String?) -> String? {
        guard let value else { return nil }
        var tokens = value.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard !tokens.isEmpty else { return nil }

        if let service,
           let last = tokens.last,
           CanonicalMorphology.comparableText(last) == CanonicalMorphology.comparableText(service) {
            tokens.removeLast()
            if tokens.last.map({ ["через", "via", "using", "у", "в", "по"].contains(CanonicalMorphology.comparableText($0)) }) == true {
                tokens.removeLast()
            }
        }

        if let last = tokens.last {
            let forms = CanonicalMorphology.forms(for: last)
            let isTelephoneChannel = forms.contains { form in
                ["телефон", "мобільн", "мобильн", "phone", "cellular"].contains { form.hasPrefix($0) }
            }
            if isTelephoneChannel {
                tokens.removeLast()
                if tokens.last.map({ ["через", "via", "using", "по", "by"].contains(CanonicalMorphology.comparableText($0)) }) == true {
                    tokens.removeLast()
                }
            }
        }

        let result = tokens.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return result.isEmpty ? nil : result
    }

    private func contactDetailPerson(_ value: String?, excludingService service: String?) -> String? {
        guard let value = communicationPerson(value, excludingService: service) else { return nil }
        let structuralRoots = [
            "контакт", "телефон", "номер", "email", "mail", "пошт", "електрон", "адрес",
            "contact", "phone", "number", "address"
        ]
        let tokens = value.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let person = tokens.filter { token in
            let normalized = CanonicalMorphology.comparableText(token)
            return !structuralRoots.contains { normalized.hasPrefix($0) }
        }.joined(separator: " ")
        let nonPersonDescriptors: Set<String> = [
            "мій", "моя", "моє", "мої", "мои", "мой", "моя", "my",
            "всі", "усі", "все", "all"
        ]
        let personTokens = person.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map {
            CanonicalMorphology.comparableText(String($0))
        }
        return personTokens.isEmpty || personTokens.allSatisfy(nonPersonDescriptors.contains) ? nil : person
    }


    private func locationPhrase(in original: String) -> String? {
        let markers = [" до ", " у ", " в ", " біля ", " поруч із ", " near ", " to "]
        return markers.compactMap { marker -> String? in
            guard let range = original.range(of: marker, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
            var value = String(original[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            let temporalSuffix = #"\s+(?:на\s+)?(?:сьогодні|завтра|післязавтра|сегодня|послезавтра|today|tomorrow|heute|morgen)(?:\s+.*)?$"#
            if let suffix = value.range(of: temporalSuffix, options: [.regularExpression, .caseInsensitive]) {
                value = String(value[..<suffix.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            }
            return value.isEmpty ? nil : value
        }.first
    }

    private func navigationDestination(in original: String) -> String? {
        let patterns = [
            #"^\s*(?:веди|проведи|navigate|take me|приведи)\s+(?:мене\s+|меня\s+)?(.+?)\s*$"#,
            #"^\s*(?:їхати|ехать|go)\s+(.+?)\s*$"#,
            #"(?:маршрут|дорог\p{L}*|шлях\p{L}*|путь\p{L}*|route|directions|path)\s+(?:до|на|у|в|to)\s+(.+?)\s*$"#
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
        ["температур", "холодн", "спекотн", "жарк", "чи буде дощ", "будет дождь", "вітр", "ветер", "прогноз", "weather", "rain", "cold", "hot", "wind", "forecast"].contains(where: text.contains)
    }

    private func photoQueryEntities(frame: CanonicalSemanticFrame, original: String) -> [String: String] {
        if frame.modifiers.contains("latest") || frame.modifiers.contains("penultimate") {
            return ["photo_query_kind": "recent", "query": "recent"]
        }
        if frame.modifiers.contains("all") {
            return ["photo_query_kind": "all", "query": "all"]
        }
        var metadata: [String: String] = [:]
        if let temporal = frame.temporal,
           temporal.relativeDayOffset != nil || temporal.calendarDay != nil || temporal.weekday != nil {
            metadata["photo_date_filter"] = "true"
        }
        if let place = photoLocationSubject(original) {
            metadata["photo_location_query"] = place
        }
        if !metadata.isEmpty {
            metadata["photo_query_kind"] = "metadata"
            metadata["query"] = "metadata"
            return metadata
        }
        let subject = semanticPhotoSubject(original)
        if subject.isEmpty { return ["photo_query_kind": "recent", "query": "recent"] }
        return ["photo_query_kind": "semantic", "query": subject]
    }

    private func photoLocationSubject(_ original: String) -> String? {
        let explicitPatterns = [
            #"\b(?:у|в)\s+(?:місті|городе|city)\s+([\p{L}'’ -]{2,80})$"#,
            #"\b(?:з|із|зі|from)\s+(?:міста|города|city)?\s*([\p{L}'’ -]{2,80})$"#
        ]
        for pattern in explicitPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: original, range: NSRange(original.startIndex..., in: original)),
                  let range = Range(match.range(at: 1), in: original) else { continue }
            let value = original[range].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            let last = value.lowercased().split(separator: " ").last.map(String.init) ?? ""
            if ["ою", "ею", "ом", "ем", "ами", "ями"].contains(where: last.hasSuffix) { return nil }
            if !value.isEmpty { return String(value) }
        }
        return nil
    }

    private func semanticPhotoSubject(_ original: String) -> String {
        // Keep the content-bearing part of the request while removing only
        // structural action/source/object tokens. This is deliberately role
        // based: it does not encode any photo subject, brand, place or an
        // acceptance-test phrase.
        let actionOrObjectRoots = [
            "знайд", "пошук", "покаж", "відкр", "найд", "поищ", "откр",
            "find", "search", "show", "open",
            "фото", "фотограф", "світлин", "знім", "сним", "picture", "image"
        ]
        let structuralWords: Set<String> = [
            "у", "в", "на", "серед", "поміж", "из", "среди", "among", "in", "from",
            "моє", "мої", "моїх", "мою", "мій", "моя", "мои", "моих", "my", "the", "a",
            "всі", "усі", "все", "all", "every"
        ]
        return lexicalTokens(original).filter { token in
            !structuralWords.contains(token) &&
                !actionOrObjectRoots.contains(where: token.hasPrefix)
        }.joined(separator: " ")
    }

    private func mediaSubject(_ original: String, app: String) -> String {
        var value = original.replacingOccurrences(of: app, with: "", options: [.caseInsensitive, .diacriticInsensitive])
        value = value.replacingOccurrences(
            of: #"^\s*(?:увімк\p{L}*|включ\p{L}*|програ\p{L}*|воспроизвед\p{L}*|знайд\p{L}*|найд\p{L}*|play|listen(?: to)?|find)\s+"#,
            with: "", options: [.regularExpression, .caseInsensitive]
        )
        value = value.replacingOccurrences(
            of: #"\s+(?:в|у|через|on|in)\s*$"#,
            with: "", options: [.regularExpression, .caseInsensitive]
        )
        return value.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func confidence(_ frame: CanonicalSemanticFrame) -> Double {
        let filled = [frame.action != nil, frame.object != nil, frame.source != nil, frame.person != nil, frame.service != nil, frame.app != nil, frame.location != nil, frame.temporal != nil, frame.numeric != nil, frame.contextReference != nil, frame.compound != nil].filter { $0 }.count
        return min(1, 0.55 + Double(filled) * 0.08)
    }
}
