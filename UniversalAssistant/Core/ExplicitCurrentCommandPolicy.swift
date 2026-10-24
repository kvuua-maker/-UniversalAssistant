import Foundation

/// Enforces the product invariant that roles explicitly stated in the current
/// command outrank recovered context, defaults and fuzzy catalogue evidence.
/// This layer never chooses a provider; it only preserves typed user roles.
/// Final current-command role normalization performed as part of canonical
/// resolution. Downstream routing and execution may not mutate these roles.
enum CanonicalCurrentCommandRoleNormalizer {
    static func apply(to command: StructuredCommand) -> StructuredCommand {
        var intent = command.intent
        var entities = command.entities
        var constraints = command.constraints
        var needsClarification = command.needsClarification

        // Public iOS does not expose destinations for the global Wi-Fi,
        // Bluetooth or Settings panes. Converge explicit OPEN requests for
        // those panes on one truthful system boundary instead of letting the
        // words collide with app-open or BLE device-control families.
        let currentTokens = tokenize(command.originalText)
        let openRoots = ["відк", "покаж", "перейд", "open", "show"]
        let asksToOpen = currentTokens.contains { token in
            openRoots.contains(where: token.hasPrefix)
        }
        let appActionRoots = openRoots + ["запуст", "launch", "go"]
        let requestsCameraCapture = currentTokens.contains(where: {
            $0.hasPrefix("фотографув") || $0.hasPrefix("сфотограф") || $0.hasPrefix("знім") || $0 == "capture"
        })
        let hasPhotoQueryRoles = command.entities["photo_query_kind"] != nil ||
            command.entities["photo_location_query"] != nil || command.entities["photo_date_filter"] == "true"
        if let application = CanonicalSpeechEntityRegistry.applicationID(in: command.originalText),
           currentTokens.contains(where: { token in appActionRoots.contains(where: token.hasPrefix) }),
           !(application == "camera" && requestsCameraCapture),
           !(application == "photos" && hasPhotoQueryRoles) {
            intent = .open
            entities["app"] = application
            entities["requested_action"] = "open"
            entities["explicit_slot_precedence"] = "current_command"
            entities.removeValue(forKey: "clarification_options")
            entities.removeValue(forKey: "clarification_role")
            needsClarification = false
        }
        let namesApplicationSettings = currentTokens.contains("universalassistant") ||
            currentTokens.contains(where: { $0.hasPrefix("застосунк") || $0.hasPrefix("додатк") || $0.hasPrefix("програм") })
        let namesGlobalSystemPane = currentTokens.contains("bluetooth") ||
            currentTokens.contains("блютуз") ||
            currentTokens.contains("wifi") ||
            (currentTokens.contains("wi") && currentTokens.contains("fi"))
        if asksToOpen && namesGlobalSystemPane {
            intent = .settings
            entities = [
                "settings_target": namesApplicationSettings ? "application" : "system",
                "explicit_slot_precedence": "current_command"
            ]
            needsClarification = false
        }

        // Opening Apple's Voice Memos app and starting a recording owned by
        // UniversalAssistant are different capabilities. iOS exposes no
        // public Voice Memos launch/recording contract, while the app's own
        // recorder is legitimate. Preserve that distinction by action, not by
        // a phrase or an app-specific destination URL.
        if entities["app"] == "voice-memos" {
            let tokens = currentTokens
            let startRoots = ["увімк", "включ", "почн", "запуст", "start", "record"]
            if tokens.contains(where: { token in startRoots.contains(where: token.hasPrefix) }) {
                intent = .audioRecord
                entities.removeValue(forKey: "app")
                entities["recorder_action"] = "start"
                entities["explicit_slot_precedence"] = "current_command"
                needsClarification = false
            }
        }

        if intent == .contactCall {
            let explicitChannel = explicitCommunicationChannel(in: command.originalText)
            if let explicitChannel {
                entities["call_service"] = explicitChannel
                entities["explicit_channel"] = explicitChannel
                entities["explicit_slot_precedence"] = "current_command"
            } else if hasCommunicationChannelMarker(in: command.originalText) {
                // A scoped fuzzy resolution (for example a clipped app name
                // after “через”) is stronger than the telephone default. An
                // unresolved named channel must clarify instead of silently
                // becoming Phone.
                if let recovered = entities["call_service"], recovered != "telephone",
                   entities["service_resolution"] != "unresolved" {
                    entities["explicit_channel"] = recovered
                    entities["explicit_slot_precedence"] = "current_command_scoped_evidence"
                } else {
                    entities.removeValue(forKey: "call_service")
                    entities.removeValue(forKey: "explicit_channel")
                    needsClarification = true
                }
            } else {
                entities["call_service"] = "telephone"
                entities["explicit_channel"] = "telephone"
                entities["explicit_slot_precedence"] = "current_command_default"
            }
            if entities["contact"] != nil || entities["phone_number"] != nil {
                if !hasCommunicationChannelMarker(in: command.originalText) || entities["call_service"] != nil {
                    needsClarification = false
                }
            }
        } else if intent == .messageCompose,
                  let channel = explicitCommunicationChannel(in: command.originalText) {
            entities["message_service"] = channel
            entities["explicit_channel"] = channel
            entities["explicit_slot_precedence"] = "current_command"
        }

        if intent == .weather,
           let location = explicitWeatherLocation(in: command.originalText) {
            entities["location"] = CanonicalLocalityNormalizer.normalize(location)
            entities.removeValue(forKey: "near_current_location")
            entities["explicit_location"] = "true"
            entities["explicit_slot_precedence"] = "current_command"
        }

        if intent == .mediaSearch {
            let tokens = tokenize(command.originalText)
            let playRoots = ["увімк", "включ", "програ", "відтвор", "play", "listen"]
            if tokens.contains(where: { token in playRoots.contains(where: token.hasPrefix) }) {
                entities["media_action"] = "play"
            }
        }

        do {
            let tokens = tokenize(command.originalText)
            let createRoots = [
                "створ", "зроб", "сформ", "згенер", "збереж", "перетвор",
                "create", "make", "generate", "save", "convert"
            ]
            let asksForPDF = tokens.contains("pdf")
            let asksToCreate = tokens.contains { token in createRoots.contains(where: token.hasPrefix) }
            if asksForPDF && asksToCreate {
                entities["query"] = "pdf"
                entities["file_type"] = "public.pdf"
                entities["pdf_creation_requested"] = "true"
                let referencesText = currentTokens.contains(where: { $0.hasPrefix("текст") || $0 == "text" })
                let referencesPhoto = currentTokens.contains(where: { $0.hasPrefix("фото") || $0.hasPrefix("зображ") || $0 == "photo" || $0 == "image" })
                let convertRoots = ["перетвор", "конверт", "convert"]
                let asksToConvert = currentTokens.contains { token in convertRoots.contains(where: token.hasPrefix) }
                let referencesFile = currentTokens.contains(where: {
                    $0.hasPrefix("файл") || $0 == "file"
                }) || (asksToConvert && currentTokens.contains(where: { $0.hasPrefix("документ") || $0 == "document" }))
                if referencesText || referencesPhoto || referencesFile {
                    intent = .fileSearch
                    entities["pdf_source_mode"] = referencesText ? "text" : (referencesPhoto ? "photo" : "document")
                    entities.removeValue(forKey: "capture_mode")
                    entities.removeValue(forKey: "input_source")
                } else {
                    // Bare PDF creation is a direct document-scanner workflow,
                    // not a generic clarification or source chooser.
                    intent = .cameraCapture
                    entities["pdf_source_mode"] = "document"
                    entities["capture_mode"] = "text_scan"
                    entities["input_source"] = "document_camera"
                    entities["output_format"] = "pdf"
                }
                needsClarification = false
            }
        }

        // A clipped device imperative is structurally incomplete, not an
        // informational query. It must clarify instead of leaking to Google.
        let incompleteActionRoots = ["відк", "покаж", "перейд", "переид", "запуст", "подзвон", "зателефон", "набер", "напиш"]
        let fillerTokens: Set<String> = ["у", "в", "до", "через", "мені", "мне", "to", "in"]
        let structurallyIncomplete = currentTokens.first.map { first in
            incompleteActionRoots.contains(where: first.hasPrefix) &&
                currentTokens.dropFirst().allSatisfy(fillerTokens.contains)
        } ?? false
        if structurallyIncomplete,
           CanonicalSpeechEntityRegistry.applicationID(in: command.originalText) == nil {
            intent = .open
            entities.removeValue(forKey: "query")
            entities["incomplete_system_command"] = "true"
            needsClarification = true
        }

        // Fuzzy catalogue recovery may help detect a family, but it must never
        // replace an unregistered proper noun with a different registered
        // brand. Only exact current-command evidence can become a hard brand.
        if let brand = constraints.brand,
           BrandOfficialDestinationRegistry.match(inText: command.originalText) == nil,
           !hasCredibleCurrentBrandEvidence(command, brand: brand) {
            constraints.brand = nil
            constraints.hardConstraintKeys.remove("brand")
            entities.removeValue(forKey: "brand")
            if entities["catalog_entity_id"]?.hasPrefix("canonical.brand.") == true {
                entities.removeValue(forKey: "catalog_entity_id")
                entities.removeValue(forKey: "catalog_match_mechanism")
                entities.removeValue(forKey: "catalog_match_confidence")
                entities["catalog_fuzzy_brand_rejected"] = "true"
            }
        }

        if let location = entities["location"], !location.isEmpty {
            entities["location"] = CanonicalLocalityNormalizer.normalize(location)
        }
        if let destination = entities["destination"], !destination.isEmpty,
           !destination.contains(",") {
            entities["destination"] = CanonicalLocalityNormalizer.normalize(destination)
        }

        return .init(
            id: command.id,
            originalText: command.originalText,
            normalizedText: command.normalizedText,
            language: command.language,
            intent: intent,
            entities: entities,
            constraints: constraints,
            risk: command.risk,
            needsClarification: needsClarification
        )
    }

    private static func explicitCommunicationChannel(in original: String) -> String? {
        if let channel = CanonicalSpeechEntityRegistry.communicationChannel(in: original) { return channel }
        let tokens = Set(tokenize(original))
        if !Set(["signal", "сигнал"]).isDisjoint(with: tokens) { return "signal" }
        let telephoneRoots = ["телефон", "телефоном", "звичайний", "мобільний", "мобильный", "phone", "cellular"]
        if tokens.contains(where: { token in telephoneRoots.contains(where: token.hasPrefix) }) {
            return "telephone"
        }
        return nil
    }

    private static func hasCommunicationChannelMarker(in original: String) -> Bool {
        let markers: Set<String> = ["через", "via", "using", "канал", "каналом", "сервіс", "сервис"]
        return !markers.isDisjoint(with: Set(tokenize(original)))
    }

    private static func explicitWeatherLocation(in original: String) -> String? {
        var value = original
        // The temporal analyzer may retain adjacent city tokens in its surface
        // expression (for example, "завтра Київ"). Removing that whole value
        // would erase explicit location evidence. Strip only known temporal
        // vocabulary below and preserve every remaining current-command token.
        let structural = [
            #"\b(?:погода|погоду|прогноз|температура|температуру|weather|forecast)\b"#,
            #"\b(?:покажи|скажи|яка|який|якою|буде|подивись|дізнайся|чи|холодно|тепло|спекотно|жарко|дощ|сніг|show|tell|what|will|be|cold|warm|hot|rain|snow)\b"#,
            #"\b(?:сьогодні|завтра|післязавтра|сегодня|послезавтра|today|tomorrow)\b"#,
            #"\b(?:наступн\p{L}*|следующ\p{L}*|next)?\s*(?:понеділ\p{L}*|понедель\p{L}*|monday|вівтор\p{L}*|вторник\p{L}*|tuesday|серед\p{L}*|сред\p{L}*|wednesday|четвер\p{L}*|thursday|п['’]?ятниц\p{L}*|пятниц\p{L}*|friday|субот\p{L}*|суббот\p{L}*|saturday|неділ\p{L}*|воскрес\p{L}*|sunday)\b"#,
            #"\b(?:[0-3]?\d(?:[./-][01]?\d(?:[./-]\d{2,4})?|\s+(?:січ\p{L}*|январ\p{L}*|лют\p{L}*|феврал\p{L}*|берез\p{L}*|март\p{L}*|квіт\p{L}*|апрел\p{L}*|трав\p{L}*|май|черв\p{L}*|июн\p{L}*|лип\p{L}*|июл\p{L}*|серп\p{L}*|август\p{L}*|верес\p{L}*|сентябр\p{L}*|жовт\p{L}*|октябр\p{L}*|листопад\p{L}*|ноябр\p{L}*|груд\p{L}*|декабр\p{L}*)(?:\s+\d{4})?))\b"#,
            #"\b(?:о|об|at)?\s*[0-2]?\d[:.]\d{2}\b"#,
            #"\b(?:там|тут|де|я|ми|перебуваю|перебуваємо|знаходжуся|знаходимося|поруч|поблизу|nearby|here)\b"#
        ]
        for pattern in structural {
            value = value.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        value = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        value = value.replacingOccurrences(
            of: #"\b(?:на|у|в|at|in|for)\s+(?=(?:на|у|в|at|in|for)?(?:\s|$))"#,
            with: " ", options: [.regularExpression, .caseInsensitive]
        ).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        value = value.replacingOccurrences(
            of: #"^(?:на|у|в|для|at|in|for)\s+"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        value = value.replacingOccurrences(
            of: #"\s+(?:на|у|в|at|in|for)$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        ).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !value.isEmpty else { return nil }
        let tokens = tokenize(value)
        guard tokens.contains(where: { token in
            !["на", "у", "в", "для", "at", "in", "for"].contains(token)
        }) else { return nil }
        return value
    }

    private static func hasCredibleCurrentBrandEvidence(_ command: StructuredCommand, brand: String) -> Bool {
        if command.entities["speech_entity_evidence"] != nil { return true }
        // The parser can receive a capability-owned registry in tests or from
        // a future provider module. Preserve its result only when the bounded
        // resolver itself recorded a strong unique match. Do not couple this
        // policy to the global production registry or trust an unscored brand.
        if command.entities["catalog_match_resolution"] == "resolved",
           (Double(command.entities["catalog_match_confidence"] ?? "") ?? 0) >= 0.78,
           (Double(command.entities["catalog_match_margin"] ?? "") ?? 0) >= 0.12 {
            return true
        }
        let brandCandidates = CanonicalCatalogEntityRegistry.candidates.filter { $0.value.kind == .brand }
        let resolver = ContextScopedEntityResolver(candidates: brandCandidates)
        let source = command.originalText.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard !source.isEmpty else { return false }
        let maximumSpan = min(4, source.count)
        for length in 1...maximumSpan {
            for start in 0...(source.count - length) {
                let subject = source[start..<(start + length)].joined(separator: " ")
                let evidence = resolver.resolveWithEvidence(subject)
                if case let .resolved(candidate) = evidence.resolution,
                   candidate.displayName == brand,
                   evidence.bestScore >= 0.72 {
                    return true
                }
            }
        }
        return false
    }

    private static func tokenize(_ value: String) -> [String] {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "uk_UA"))
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }
}
