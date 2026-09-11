import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

struct LanguageUnderstandingDocument: Equatable, Sendable {
    struct Token: Equatable, Sendable {
        let surface: String
        let normalized: String
        let morphology: String
        let morphologyForms: Set<String>
    }

    let originalText: String
    let normalizedText: String
    let tokens: [Token]
    let language: CommandLanguage
    let languageHypotheses: [String: Double]
}

protocol EvidenceAwareCommandParsing: CommandParsing {
    func parse(_ text: String, speechEvidence: VoiceRecognitionEvidence?) -> StructuredCommand
}

enum CanonicalCatalogEntityKind: String, Equatable, Sendable {
    case brand, product, provider, retailer
}

struct CanonicalCatalogEntity: Equatable, Sendable {
    let id: String
    let displayName: String
    let kind: CanonicalCatalogEntityKind
}

/// One verified candidate domain shared by Speech hints, structured semantics,
/// and the legacy compatibility extractor. These are entity names, never noisy
/// transcript substitutions; provider-supplied candidates use the same typed
/// `ScopedEntityCandidate` boundary.
enum CanonicalCatalogEntityRegistry {
    static let brandNames = [
        "Baldinini", "Nike", "Adidas", "Puma", "Zara", "Mango", "Gucci", "Prada"
    ]

    static let candidates: [ScopedEntityCandidate<CanonicalCatalogEntity>] = {
        let brands = brandNames.map { name in
            let entity = CanonicalCatalogEntity(
                id: "canonical.brand.\(name.lowercased())",
                displayName: name,
                kind: .brand
            )
            return ScopedEntityCandidate(
                value: entity,
                displayName: name,
                aliases: [name]
            )
        }
        let retailers = UkrainianRetailerRegistry.records.map { record in
            let entity = CanonicalCatalogEntity(
                id: record.id,
                displayName: record.displayName,
                kind: .retailer
            )
            return ScopedEntityCandidate(
                value: entity,
                displayName: record.displayName,
                aliases: [record.displayName, record.id]
            )
        }
        return brands + retailers
    }()
}

private struct CanonicalExternalProviderInference: Sendable {
    let intent: CommandIntent
    let domain: String
    let confidence: Double
    let evidence: Set<String>
}

/// Bridges whole-command semantic evidence into the canonical provider-neutral
/// boundary. The rules describe function domains and role combinations, not
/// acceptance phrases. A provider family must have both a domain object and a
/// compatible goal before it can supersede an unresolved/open-ended candidate.
private enum CanonicalExternalProviderBoundaryAnalyzer {
    private struct Rule: Sendable {
        let domain: String
        let intent: CommandIntent
        let objectRoots: Set<String>
        let actionRoots: Set<String>
        let minimumObjectMatches: Int
    }

    private static let rules: [Rule] = [
        .init(domain: "parcel_tracking", intent: .parcelTrack,
              objectRoots: ["посилк", "відправлен", "доставлен", "посылк", "отправлен", "parcel", "package", "shipment", "consignment", "paket", "colis"],
              actionRoots: ["відстеж", "простеж", "перевір", "статус", "покаж", "знайд", "отслед", "провер", "track", "trace", "status", "show", "find"],
              minimumObjectMatches: 1),
        .init(domain: "loyalty_benefits", intent: .productSearch,
              objectRoots: ["лояльн", "знижк", "винагород", "бонус", "персональн", "лояльност", "скидк", "вознагражден", "loyalty", "discount", "reward", "benefit", "membership"],
              actionRoots: ["покаж", "перевір", "знайд", "переліч", "доступ", "провер", "найд", "show", "check", "find", "list", "available"],
              minimumObjectMatches: 2),
        .init(domain: "grocery_delivery", intent: .groceryBasket,
              objectRoots: ["кошик", "продукт", "доставк", "корзин", "grocery", "basket", "groceries", "delivery"],
              actionRoots: ["збер", "куп", "замов", "підбер", "собер", "закаж", "assemble", "buy", "order", "build"],
              minimumObjectMatches: 2),
        .init(domain: "restaurant_reservation", intent: .reservation,
              objectRoots: ["столик", "ресторан", "бронюван", "стол", "restaurant", "table", "reservation"],
              actionRoots: ["заброн", "резерв", "book", "reserve"],
              minimumObjectMatches: 1),
        .init(domain: "product_catalog", intent: .productSearch,
              objectRoots: ["товар", "продукт", "взут", "черев", "кросів", "одяг", "сумк", "рюкзак", "ноутбук", "телефон", "мебл", "product", "item", "shoe", "boot", "clothing", "bag", "backpack", "laptop", "phone", "furniture"],
              actionRoots: ["знайд", "підбер", "покаж", "куп", "замов", "найд", "find", "search", "show", "select", "buy", "order"],
              minimumObjectMatches: 1),
        .init(domain: "ride_service", intent: .taxiSearch,
              objectRoots: ["таксі", "такси", "taxi", "ride"],
              actionRoots: ["порівн", "знайд", "виклич", "замов", "сравн", "найд", "compare", "find", "request", "book"],
              minimumObjectMatches: 1),
        .init(domain: "lodging", intent: .hotelSearch,
              objectRoots: ["готел", "хостел", "житл", "отел", "hotel", "hostel", "lodging", "accommodation"],
              actionRoots: ["підбер", "знайд", "заброн", "найд", "find", "search", "book"],
              minimumObjectMatches: 1),
        .init(domain: "tickets", intent: .ticketSearch,
              objectRoots: ["квит", "білет", "ticket", "fare"],
              actionRoots: ["знайд", "підбер", "покаж", "найд", "find", "search", "show"],
              minimumObjectMatches: 1),
        .init(domain: "commercial_service", intent: .serviceSearch,
              objectRoots: ["майстр", "ремонт", "сервіс", "услуг", "мастер", "service", "repair", "contractor"],
              actionRoots: ["знайд", "підбер", "покаж", "найд", "find", "search", "show"],
              minimumObjectMatches: 1)
    ]

    static func infer(
        document: LanguageUnderstandingDocument,
        frame: CanonicalSemanticFrame,
        currentIntent: CommandIntent
    ) -> CanonicalExternalProviderInference? {
        let externalIntents: Set<CommandIntent> = [
            .productSearch, .fashionDiscovery, .groceryBasket, .serviceSearch,
            .restaurantSearch, .reservation, .taxiSearch, .taxiCompare,
            .publicTransport, .ticketSearch, .ticketPurchaseHandoff,
            .hotelSearch, .travelPlan, .parcelTrack
        ]
        let unresolvedIntents: Set<CommandIntent> = [.unknown, .webSearch, .show, .open]
        guard externalIntents.contains(currentIntent) || unresolvedIntents.contains(currentIntent) else {
            return nil
        }
        guard frame.source == nil, frame.contextReference == nil else { return nil }
        if frame.action == .open, frame.object == .app { return nil }

        let forms = document.tokens.reduce(into: Set<String>()) { result, token in
            result.insert(token.normalized)
            result.formUnion(token.morphologyForms)
        }
        func matchedRoots(_ roots: Set<String>) -> Set<String> {
            Set(roots.filter { root in forms.contains { $0.hasPrefix(root) } })
        }

        // Rental and ride are different service contracts. Require evidence
        // from both the vehicle and rental semantic roles; counting multiple
        // spelling roots that match one token would incorrectly turn a bare
        // “car” order into rental.
        let hasVehicle = !matchedRoots(["авто", "автомоб", "машин", "car", "vehicle"]).isEmpty
        let hasRental = !matchedRoots(["оренд", "прокат", "rent", "rental", "hire"]).isEmpty
        let hasServiceGoal = !matchedRoots(["знайд", "підбер", "замов", "оренд", "найд", "find", "search", "book", "rent", "hire"]).isEmpty
        if hasVehicle, hasRental, hasServiceGoal {
            return .init(
                intent: .serviceSearch, domain: "car_rental", confidence: 0.91,
                evidence: matchedRoots(["авто", "автомоб", "машин", "car", "vehicle", "оренд", "прокат", "rent", "rental", "hire"])
            )
        }

        let candidates = rules.compactMap { rule -> CanonicalExternalProviderInference? in
            let objects = matchedRoots(rule.objectRoots)
            guard objects.count >= rule.minimumObjectMatches else { return nil }
            let actions = matchedRoots(rule.actionRoots)
            guard !actions.isEmpty else { return nil }
            let confidence = min(0.98, 0.62 + Double(objects.count) * 0.09 + Double(actions.count) * 0.07)
            return .init(intent: rule.intent, domain: rule.domain, confidence: confidence,
                         evidence: objects.union(actions))
        }
        guard let best = candidates.max(by: { $0.confidence < $1.confidence }) else { return nil }
        let runnerUp = candidates.filter { $0.domain != best.domain }.map(\.confidence).max() ?? 0
        guard best.confidence >= 0.75, best.confidence - runnerUp >= 0.08 else { return nil }
        return best
    }

    static func hasAmbiguousVehicleServiceGoal(
        document: LanguageUnderstandingDocument,
        currentIntent: CommandIntent
    ) -> Bool {
        guard [.unknown, .webSearch, .show, .open, .productSearch, .fashionDiscovery].contains(currentIntent) else {
            return false
        }
        let forms = document.tokens.reduce(into: Set<String>()) { result, token in
            result.insert(token.normalized)
            result.formUnion(token.morphologyForms)
        }
        func has(_ roots: [String]) -> Bool {
            forms.contains { value in roots.contains { value.hasPrefix($0) } }
        }
        let vehicle = has(["авто", "автомоб", "машин", "car", "vehicle"])
        let ordering = has(["замов", "закаж", "book", "order", "request"])
        let explicitRide = has(["таксі", "такси", "taxi", "ride"])
        let explicitRental = has(["оренд", "прокат", "rent", "rental", "hire"])
        return vehicle && ordering && !explicitRide && !explicitRental
    }
}

/// The single semantic entry point for typed text, final Speech transcripts,
/// App Intent parameters, and compound subcommands in the shipped graph.
///
/// LocalCommandEngine is retained only as a compatibility candidate generator
/// while the 96 families migrate. It cannot bypass structural framing,
/// confidence decisions, or protected-domain web isolation.
struct LanguageUnderstandingBlock: EvidenceAwareCommandParsing, Sendable {
    private let legacyCandidate: LocalCommandEngine
    private let analyzer: CanonicalSemanticFrameAnalyzer
    private let propositionAnalyzer: CanonicalPropositionAnalyzer
    private let applicationCandidates: [ScopedEntityCandidate<String>]
    private let serviceCandidates: [ScopedEntityCandidate<String>]
    private let catalogCandidates: [ScopedEntityCandidate<CanonicalCatalogEntity>]

    init(
        legacyCandidate: LocalCommandEngine = .init(),
        analyzer: CanonicalSemanticFrameAnalyzer = .init(),
        propositionAnalyzer: CanonicalPropositionAnalyzer = .init(),
        applicationCandidates: [ScopedEntityCandidate<String>]? = nil,
        serviceCandidates: [ScopedEntityCandidate<String>]? = nil,
        catalogCandidates: [ScopedEntityCandidate<CanonicalCatalogEntity>]? = nil
    ) {
        self.legacyCandidate = legacyCandidate
        self.analyzer = analyzer
        self.propositionAnalyzer = propositionAnalyzer
        self.applicationCandidates = applicationCandidates ?? Self.verifiedApplicationCandidates
        self.serviceCandidates = serviceCandidates ?? Self.verifiedServiceCandidates
        self.catalogCandidates = catalogCandidates ?? Self.verifiedCatalogCandidates
    }

    /// A bounded view of the exact catalog/provider candidates that this
    /// parser can actually resolve. Speech uses it only as recognition context;
    /// all execution still requires the same confidence-ranked typed resolver.
    func requestScopedCatalogVocabulary(limit: Int = 24) -> [String] {
        guard limit > 0 else { return [] }
        var seen: Set<String> = []
        return catalogCandidates
            .flatMap { [$0.displayName] + $0.aliases.sorted() }
            .compactMap { value -> String? in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                let key = trimmed.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                ).lowercased()
                return seen.insert(key).inserted ? trimmed : nil
            }
            .prefix(limit)
            .map { $0 }
    }

    func parse(_ text: String) -> StructuredCommand {
        parse(text, speechEvidence: nil)
    }

    func parse(_ text: String, speechEvidence: VoiceRecognitionEvidence?) -> StructuredCommand {
        let primary = parseAuthoritative(text)
        guard let speechEvidence else { return primary }
        let alternatives = speechEvidence.alternativeTranscripts
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .filter { $0.caseInsensitiveCompare(text) != .orderedSame }
        var selected = primary
        var selectedAlternative = false
        for alternative in alternatives {
            let candidate = parseAuthoritative(alternative)
            if shouldAdopt(candidate, over: selected) {
                selected = candidate
                selectedAlternative = true
            }
        }
        var entities = selected.entities
        entities["speech_alternative_count"] = String(alternatives.count)
        if let confidence = speechEvidence.averageSegmentConfidence {
            entities["speech_mean_confidence"] = String(format: "%.3f", confidence)
        }
        if selectedAlternative { entities["speech_selected_alternative"] = "true" }
        return .init(
            id: primary.id,
            originalText: text,
            normalizedText: selected.normalizedText,
            language: selected.language,
            intent: selected.intent,
            entities: entities,
            constraints: selected.constraints,
            risk: selected.risk,
            needsClarification: selected.needsClarification
        )
    }

    private func parseAuthoritative(_ text: String) -> StructuredCommand {
        let document = Self.document(text)
        guard !document.normalizedText.isEmpty else {
            return .init(originalText: text, normalizedText: "", language: document.language, intent: .unknown, needsClarification: true)
        }

        let legacy = legacyCandidate.parse(text)
        if legacy.entities["direct_url"] != nil {
            return authoritative(legacy, document: document, evidence: "verified_http_url")
        }

        let frameResult = analyzer.analyze(
            original: text,
            normalized: document.normalizedText,
            morphologyForms: document.tokens.map(\.morphologyForms)
        )
        var entities = legacy.entities
        var constraints = legacy.constraints
        for (key, value) in frameResult.entities { entities[key] = value }
        entities["language_understanding_version"] = "1"
        entities["semantic_confidence"] = String(format: "%.3f", frameResult.frame.confidence)

        let arithmetic = CanonicalArithmeticExpressionAnalyzer.analyze(document.normalizedText)
        if let arithmetic {
            entities["arithmetic_confidence"] = String(format: "%.3f", arithmetic.confidence)
            entities["arithmetic_evidence"] = arithmetic.evidence.sorted().joined(separator: "|")
            entities["arithmetic_step_count"] = String(arithmetic.steps.count)
        }
        var intent: CommandIntent
        if LocalUtilityEngine.canExecute(document.normalizedText),
           arithmetic != nil || !hasIncompatibleStructuredUtilityObject(frameResult.frame) {
            intent = .localUtility
        } else if LocalUtilityEngine.recognizesCurrency(document.normalizedText) {
            intent = .currencyConversion
        } else if legacy.intent == .multiStep, frameResult.frame.compound != nil {
            // LocalCommandEngine has already required every separated clause to
            // resolve to a concrete canonical command. Preserve that validated
            // typed graph before selecting any one clause's structural intent;
            // otherwise an interactive first step loses its continuation.
            intent = .multiStep
        } else if let structural = frameResult.intent {
            intent = structural
        } else {
            intent = legacy.intent
        }

        let proposition = propositionAnalyzer.infer(
            document: document,
            frame: frameResult.frame,
            currentIntent: intent,
            constraints: constraints
        )
        if let proposition {
            intent = proposition.intent
            for (key, value) in proposition.entities {
                if entities[key] == nil || key == "query" || key == "near_current_location" {
                    entities[key] = value
                }
            }
            entities["proposition_confidence"] = String(format: "%.3f", proposition.confidence)
            entities["proposition_evidence"] = proposition.evidence.sorted().joined(separator: "|")
        }

        let emergencyTarget: String? = {
            let explicit = CanonicalEmergencyNumberPolicy.explicitPermittedNumber(in: document.normalizedText)
            let emergencyContext = legacy.intent == .emergency || frameResult.frame.action == .call
            guard emergencyContext else { return nil }
            if let explicit { return explicit }
            return legacy.intent == .emergency ? CanonicalEmergencyNumberPolicy.defaultNumber() : nil
        }()
        if let emergencyTarget {
            intent = .emergency
            entities["phone_number"] = emergencyTarget
            entities["semantic_evidence"] = "typed_emergency_phone_destination"
        }

        let providerInference = emergencyTarget == nil
            ? CanonicalExternalProviderBoundaryAnalyzer.infer(
                document: document,
                frame: frameResult.frame,
                currentIntent: intent
            )
            : nil
        if let providerInference {
            intent = providerInference.intent
            entities["provider_domain"] = providerInference.domain
            entities["provider_boundary"] = "external_current_service"
            entities["provider_confidence"] = String(format: "%.3f", providerInference.confidence)
            entities["provider_evidence"] = providerInference.evidence.sorted().joined(separator: "|")
            if entities["query"] == nil { entities["query"] = text }
            entities.removeValue(forKey: "clarification_options")
            entities.removeValue(forKey: "clarification_role")
        }
        if providerInference?.domain == "car_rental" {
        if providerInference?.domain == "car_rental",
           entities["location"] == nil,
           let explicitLocation = frameResult.frame.location?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicitLocation.isEmpty {
            entities["location"] = explicitLocation
        }
            entities["serviceCategory"] = LocalServiceCategory.carRental.rawValue
        } else if providerInference == nil,
                  CanonicalExternalProviderBoundaryAnalyzer.hasAmbiguousVehicleServiceGoal(
                    document: document,
                    currentIntent: intent
                  ) {
            // “Order a car” names the object and mutation but not whether the
            // requested service is a ride or a rental. Preserve one typed
            // ambiguity instead of silently converting the local service into
            // a product/web query.
            intent = .serviceSearch
            entities["provider_domain"] = "vehicle_service"
            entities["provider_boundary"] = "typed_service_ambiguity"
            entities["clarification_options"] = "Таксі|Оренда автомобіля"
            entities["clarification_role"] = "vehicle_service"
        }

        var needsClarification = (proposition == nil && legacy.needsClarification) ||
            entities["clarification_options"] != nil
        if emergencyTarget != nil || providerInference != nil { needsClarification = false }
        if let recovered = recoverApplication(
            frame: frameResult.frame,
            document: document,
            selectedIntent: intent
        ) {
            recordResolutionEvidence(recovered, prefix: "entity_match", entities: &entities)
            // A compatibility parser may expose the raw open target as an app.
            // It is not a verified entity and must not survive an unresolved or
            // ambiguous canonical-domain decision.
            entities.removeValue(forKey: "app")
            switch recovered.resolution {
            case let .resolved(identifier):
                entities["app"] = identifier
                entities["entity_match_mechanism"] = recovered.mechanism.rawValue
                entities["entity_match_confidence"] = String(format: "%.3f", recovered.bestScore)
                if isApplicationLaunch(frameResult.frame) { intent = .open }
                needsClarification = false
            case let .ambiguous(options):
                entities["clarification_options"] = options.joined(separator: "|")
                entities["clarification_role"] = "application"
                intent = .open
                needsClarification = true
            case .unresolved:
                if isApplicationLaunch(frameResult.frame) {
                    intent = .open
                    needsClarification = true
                }
            }
        }

        if let serviceKey = serviceKey(for: intent),
           entities[serviceKey] == nil,
           let recovered = recoverService(frame: frameResult.frame, document: document, intent: intent) {
            recordResolutionEvidence(recovered, prefix: "service_match", entities: &entities)
            switch recovered.resolution {
            case let .resolved(identifier):
                entities[serviceKey] = identifier
                if intent == .messageCompose, let recipient = entities["recipient"] {
                    entities["recipient"] = communicationRecipient(
                        recipient,
                        excludingResolvedService: identifier
                    )
                }
                entities["service_match_mechanism"] = recovered.mechanism.rawValue
                entities["service_match_confidence"] = String(format: "%.3f", recovered.bestScore)
                if entities["clarification_role"] == "service_channel" {
                    entities.removeValue(forKey: "clarification_options")
                    entities.removeValue(forKey: "clarification_role")
                }
                if entities["clarification_options"] == nil,
                   entities[intent == .contactCall ? "contact" : "recipient"] != nil {
                    needsClarification = false
                }
            case let .ambiguous(options):
                entities["clarification_options"] = options.joined(separator: "|")
                entities["clarification_role"] = "service_channel"
                needsClarification = true
            case .unresolved:
                entities["service_resolution"] = "unresolved"
                needsClarification = true
            }
        }
        if intent == .messageCompose,
           let service = entities["message_service"]?.lowercased(),
           service == "email",
           let address = Self.emailAddress(in: text) {
            entities["recipient"] = address
        }
        if intent == .messageCompose,
           entities["message_service"]?.lowercased() == MessengerKind.telegram.rawValue,
           let username = Self.explicitMessengerUsername(in: text) {
            entities["recipient"] = username
        }
        // The public Apple Messages composer is the canonical unqualified
        // communication channel. Make the default explicit in the typed frame
        // so no downstream renderer/provider can reinterpret a generic message
        // as email or an arbitrary messenger fallback.
        if intent == .messageCompose,
           entities["message_service"] == nil,
           entities["clarification_role"] != "service_channel" {
            entities["message_service"] = MessengerKind.messages.rawValue
            entities["service_resolution"] = "canonical_default"
        }

        if let recovered = recoverCatalog(
            document: document,
            intent: intent,
            constraints: constraints
        ) {
            recordResolutionEvidence(recovered, prefix: "catalog_match", entities: &entities)
            switch recovered.resolution {
            case let .resolved(candidate):
                entities[candidate.kind.rawValue] = candidate.displayName
                entities["catalog_entity_id"] = candidate.id
                entities["catalog_match_mechanism"] = recovered.mechanism.rawValue
                entities["catalog_match_confidence"] = String(format: "%.3f", recovered.bestScore)
                switch candidate.kind {
                case .brand:
                    constraints.brand = candidate.displayName
                    constraints.hardConstraintKeys.insert("brand")
                case .product:
                    entities["product"] = candidate.displayName
                case .provider:
                    entities["provider"] = candidate.displayName
                case .retailer:
                    entities["retailer"] = candidate.displayName
                }
                // A verified entity from a catalog-only candidate domain plus
                // typed commerce constraints is structural evidence for a
                // provider-neutral product request. This is a two-pass role
                // decision: the entity never promotes an already recognized
                // system/personal intent and a weak/unresolved name never
                // manufactures commerce semantics.
                if intent == .unknown || intent == .webSearch {
                    intent = .productSearch
                    needsClarification = false
                }
            case let .ambiguous(options):
                entities["clarification_options"] = options.joined(separator: "|")
                entities["clarification_role"] = "catalog"
                needsClarification = true
            case .unresolved:
                break
            }
        }

        // Availability and a provider mutation are distinct typed operations.
        // A subsequent ordinal selection may advance an already explicit
        // booking request, but it never turns a plain restaurant search into a
        // booking. The executor therefore receives the selected slot as typed
        // state rather than reparsing the raw sentence.
        if intent == .reservation,
           entities["reservation_operation"] == "availability",
           entities["reservation_requested_mutation"] == "book",
           constraints.ordinal != nil {
            entities["reservation_operation"] = "book"
        }

        if shouldFailClosed(frame: frameResult.frame, selectedIntent: intent) {
            intent = failClosedIntent(for: frameResult.frame)
            needsClarification = true
        }
        if [.contactLookup, .contactCall].contains(intent),
           entities["contact"] == nil, entities["phone_number"] == nil {
            needsClarification = true
        }
        if requiresTemporalClarification(intent: intent, entities: entities) {
            entities["clarification_role"] = "temporal"
            needsClarification = true
        }

        let language = document.language == .automatic ? legacy.language : document.language
        return .init(
            id: legacy.id,
            originalText: text,
            normalizedText: document.normalizedText,
            language: language,
            intent: intent,
            entities: entities,
            constraints: constraints,
            risk: intent == .emergency ? .emergency : legacy.risk,
            needsClarification: needsClarification || intent == .unknown
        )
    }

    /// A local-utility recognizer may observe digits or separators inside a
    /// typed personal/system object (for example a Calendar date). That weak
    /// lexical evidence cannot preempt the structural family. A complete
    /// typed arithmetic expression remains authoritative across noun/action
    /// collisions such as an imperative division versus generic sharing.
    private func hasIncompatibleStructuredUtilityObject(_ frame: CanonicalSemanticFrame) -> Bool {
        guard let object = frame.object else { return false }
        return [
            .calendar, .reminder, .timer, .alarm, .contact, .settings,
            .file, .photo, .document, .place, .weather, .travelTime,
            .note, .audio, .audioRoute, .media
        ].contains(object)
    }

    /// Apple alternatives may complete a role only inside the same structural
    /// intent family. They cannot manufacture a different privileged action.
    private func shouldAdopt(_ candidate: StructuredCommand, over primary: StructuredCommand) -> Bool {
        guard candidate.intent == primary.intent, candidate.intent != .unknown,
              candidate.intent != .webSearch else { return false }
        if primary.needsClarification && !candidate.needsClarification { return true }
        let roleKeys: Set<String> = [
            "app", "contact", "recipient", "call_service", "message_service",
            "location", "destination", "query", "source_text", "target_language",
            "brand", "product", "provider", "retailer", "catalog_entity_id"
        ]
        let primaryRoles = primary.entities.keys.filter(roleKeys.contains).count
        let candidateRoles = candidate.entities.keys.filter(roleKeys.contains).count
        return !candidate.needsClarification && candidateRoles > primaryRoles
    }

    private func requiresTemporalClarification(
        intent: CommandIntent,
        entities: [String: String]
    ) -> Bool {
        if entities["temporal_requires_clarification"] == "true" { return true }
        switch intent {
        case .deviceAction where entities["system_action"] == "timer":
            return Int(entities["duration_seconds"] ?? "") == nil
        case .deviceAction where entities["system_action"] == "alarm":
            return Int(entities["hour"] ?? "") == nil ||
                Int(entities["minute"] ?? "") == nil
        case .calendarCreate:
            let hasDay = entities["relative_day_offset"] != nil ||
                entities["calendar_day"] != nil ||
                entities["weekday"] != nil
            return !hasDay || entities["hour"] == nil || entities["minute"] == nil
        case .reminderCreate:
            return entities["relative_interval_seconds"] == nil &&
                entities["relative_day_offset"] == nil &&
                entities["calendar_day"] == nil &&
                entities["weekday"] == nil
        case .reservation where entities["reservation_operation"] == "availability":
            let hasDay = entities["relative_day_offset"] != nil ||
                entities["calendar_day"] != nil || entities["weekday"] != nil
            return entities["party_size"] == nil || !hasDay ||
                entities["hour"] == nil || entities["minute"] == nil
        default:
            return false
        }
    }

    static func document(_ text: String) -> LanguageUnderstandingDocument {
        let compatibility = text.precomposedStringWithCompatibilityMapping
        var normalized = compatibility.replacingOccurrences(
            of: "[‐‑‒–—―]",
            with: "-",
            options: .regularExpression
        )
        for apostrophe in ["’", "ʼ", "‘", "ʻ"] {
            normalized = normalized.replacingOccurrences(of: apostrophe, with: "'")
        }
        normalized = normalized
            .lowercased(with: Locale(identifier: "uk_UA"))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        normalized = StructuredNumberNormalizer.normalize(normalized)

        let hypotheses = languageHypotheses(normalized)
        let language = commandLanguage(normalized, hypotheses: hypotheses)
        let tokens = compatibility
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
            .map { token in
                let surface = String(token)
                let lowered = surface.precomposedStringWithCompatibilityMapping
                    .lowercased(with: Locale(identifier: "uk_UA"))
                // Diacritic folding is useful for Latin proper names, but in
                // Cyrillic it destroys lexical letters (notably Ukrainian й)
                // and breaks action/morphology roles: “знайди” became
                // “знаиди”. Preserve Cyrillic orthography exactly.
                let containsCyrillic = lowered.unicodeScalars.contains {
                    (0x0400...0x052F).contains(Int($0.value))
                }
                let folded = containsCyrillic ? lowered : lowered.folding(
                    options: .diacriticInsensitive,
                    locale: Locale(identifier: "en_US_POSIX")
                )
                let forms = CanonicalMorphology.forms(for: folded)
                return LanguageUnderstandingDocument.Token(
                    surface: surface,
                    normalized: folded,
                    morphology: CanonicalMorphology.representative(for: folded),
                    morphologyForms: forms
                )
            }
        return .init(
            originalText: text,
            normalizedText: normalized,
            tokens: tokens,
            language: language,
            languageHypotheses: hypotheses
        )
    }

    private func authoritative(
        _ command: StructuredCommand,
        document: LanguageUnderstandingDocument,
        evidence: String
    ) -> StructuredCommand {
        var entities = command.entities
        entities["language_understanding_version"] = "1"
        entities["semantic_evidence"] = evidence
        return .init(
            id: command.id,
            originalText: command.originalText,
            normalizedText: document.normalizedText,
            language: document.language == .automatic ? command.language : document.language,
            intent: command.intent,
            entities: entities,
            constraints: command.constraints,
            risk: command.risk,
            needsClarification: command.needsClarification
        )
    }

    private func recordResolutionEvidence<Value: Equatable & Sendable>(
        _ evidence: ScopedEntityResolutionEvidence<Value>,
        prefix: String,
        entities: inout [String: String]
    ) {
        entities["\(prefix)_confidence"] = String(format: "%.3f", evidence.bestScore)
        entities["\(prefix)_margin"] = String(format: "%.3f", evidence.confidenceMargin)
        entities["\(prefix)_mechanism"] = evidence.mechanism.rawValue
        entities["\(prefix)_resolution"] = switch evidence.resolution {
        case .resolved: "resolved"
        case .ambiguous: "ambiguous"
        case .unresolved: "unresolved"
        }
    }

    private func recoverApplication(
        frame: CanonicalSemanticFrame,
        document: LanguageUnderstandingDocument,
        selectedIntent: CommandIntent
    ) -> ScopedEntityResolutionEvidence<String>? {
        // Application recovery may complete an OPEN_APP frame, but it cannot
        // override an already selected concrete system or personal family just
        // because that command also carries an "open" action.
        guard selectedIntent == .open || (selectedIntent == .unknown && isApplicationLaunch(frame)) else { return nil }
        let actionMorphologyRoots: Set<String> = [
            "відкр", "откр", "запуст", "перейд", "програм", "застос", "прилож"
        ]
        let exactActionTokens: Set<String> = ["open", "launch", "app"]
        let subject = document.tokens
            .filter { token in
                token.morphologyForms.allSatisfy { form in
                    !exactActionTokens.contains(form) &&
                        !actionMorphologyRoots.contains(where: form.hasPrefix)
                }
            }
            .map(\.surface)
            .joined(separator: " ")
        guard !subject.isEmpty else {
            return .init(
                resolution: .unresolved,
                bestScore: 0,
                confidenceMargin: 0,
                mechanism: .unresolved
            )
        }
        return ContextScopedEntityResolver(candidates: applicationCandidates)
            .resolveWithEvidence(subject)
    }

    private func serviceKey(for intent: CommandIntent) -> String? {
        switch intent {
        case .contactCall: "call_service"
        case .messageCompose: "message_service"
        default: nil
        }
    }

    private func recoverService(
        frame: CanonicalSemanticFrame,
        document: LanguageUnderstandingDocument,
        intent: CommandIntent
    ) -> ScopedEntityResolutionEvidence<String>? {
        guard serviceKey(for: intent) != nil,
              frame.action == .call || frame.action == .message || frame.action == .share,
              !serviceCandidates.isEmpty else { return nil }
        let strongMarkers: Set<String> = [
            "через", "via", "using", "канал", "channel", "сервіс", "сервис",
            "service", "месенджер", "мессенджер", "messenger"
        ]
        let weakMarkers: Set<String> = ["у", "в", "по"]
        let normalized = document.tokens.map(\.normalized)
        if let markerIndex = normalized.indices.first(where: { strongMarkers.contains(normalized[$0]) })
            ?? normalized.indices.first(where: { weakMarkers.contains(normalized[$0]) }),
           markerIndex + 1 < document.tokens.count {
            let subject = document.tokens[(markerIndex + 1)...].map(\.surface).joined(separator: " ")
            let evidence = ContextScopedEntityResolver(candidates: serviceCandidates).resolveWithEvidence(subject)
            let strongScope = strongMarkers.contains(normalized[markerIndex])
            if strongScope || evidence.isResolved { return evidence }
        }

        // A communication action establishes the family, but it does not turn
        // every person token into a channel candidate. Fuzzy recovery is safe
        // only inside a structural SERVICE/CHANNEL scope. Exact canonical
        // service names are already represented by frame.service upstream.
        return nil
    }

    private func communicationRecipient(_ value: String, excludingResolvedService service: String) -> String? {
        var tokens = value.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "@" })
            .map(String.init)
        if service == "email" {
            tokens.removeAll { token in
                CanonicalMorphology.forms(for: token).contains { form in
                    ["email", "mail", "пошт", "почт", "електрон", "электрон", "лист"].contains {
                        form.hasPrefix($0)
                    }
                }
            }
            let output = tokens.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return output.isEmpty ? nil : output
        }
        guard let candidate = serviceCandidates.first(where: { $0.value == service }) else { return value }
        let resolver = ContextScopedEntityResolver(candidates: [candidate])
        guard let index = tokens.firstIndex(where: { token in
            if case .resolved = resolver.resolve(token) { return true }
            return false
        }) else { return value }
        tokens.remove(at: index)
        if index > 0, tokens.indices.contains(index - 1),
           ["через", "via", "using", "у", "в", "по", "канал", "каналом"].contains(tokens[index - 1].lowercased()) {
            tokens.remove(at: index - 1)
        }
        let output = tokens.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }

    private static func emailAddress(in text: String) -> String? {
        let pattern = #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#
        guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return String(text[range])
    }

    private static func explicitMessengerUsername(in text: String) -> String? {
        let pattern = #"@[A-Z0-9_]+"#
        guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        return String(text[range])
    }

    private func recoverCatalog(
        document: LanguageUnderstandingDocument,
        intent: CommandIntent,
        constraints: CommandConstraints
    ) -> ScopedEntityResolutionEvidence<CanonicalCatalogEntity>? {
        let catalogFamily = [.productSearch, .fashionDiscovery, .groceryBasket].contains(intent)
        let constrainedUnresolvedRequest = (intent == .unknown || intent == .webSearch) &&
            !constraints.hardConstraintKeys.isEmpty
        guard (catalogFamily || constrainedUnresolvedRequest), !catalogCandidates.isEmpty else { return nil }
        let ignoredMorphology: Set<String> = [
            "знайд", "пошук", "покаж", "підбер", "куп", "найд", "поищ", "покаж",
            "find", "search", "show", "buy", "brand", "бренд", "product", "товар",
            "price", "цін", "цен", "under", "грив", "uah", "usd", "eur"
        ]
        let subjects = document.tokens.filter { token in
            token.morphologyForms.allSatisfy { form in !ignoredMorphology.contains(where: form.hasPrefix) } &&
                !token.normalized.allSatisfy(\.isNumber)
        }
        guard !subjects.isEmpty else { return nil }
        return bestScopedResolution(in: subjects, candidates: catalogCandidates)
    }

    private func bestScopedResolution<Value: Equatable & Sendable>(
        in tokens: [LanguageUnderstandingDocument.Token],
        candidates: [ScopedEntityCandidate<Value>]
    ) -> ScopedEntityResolutionEvidence<Value> {
        guard !tokens.isEmpty else {
            return .init(resolution: .unresolved, bestScore: 0, confidenceMargin: 0, mechanism: .unresolved)
        }
        let resolver = ContextScopedEntityResolver(candidates: candidates)
        var subjects = [tokens.map(\.surface).joined(separator: " ")]
        for length in 1...min(3, tokens.count) {
            for start in 0...(tokens.count - length) {
                subjects.append(tokens[start..<(start + length)].map(\.surface).joined(separator: " "))
            }
        }
        return subjects
            .map { resolver.resolveWithEvidence($0) }
            .max {
                if $0.bestScore == $1.bestScore { return $0.confidenceMargin < $1.confidenceMargin }
                return $0.bestScore < $1.bestScore
            } ?? .init(resolution: .unresolved, bestScore: 0, confidenceMargin: 0, mechanism: .unresolved)
    }

    /// “Start/launch” is structurally a set action for timers and alarms, but
    /// becomes an app launch only when no concrete device/personal object was
    /// identified. This keeps capability selection role-driven rather than
    /// depending on one spelling of an application command.
    private func isApplicationLaunch(_ frame: CanonicalSemanticFrame) -> Bool {
        frame.action == .open || frame.object == .app ||
            (frame.action == .set && frame.object == nil)
    }

    private func shouldFailClosed(
        frame: CanonicalSemanticFrame,
        selectedIntent: CommandIntent
    ) -> Bool {
        guard selectedIntent == .unknown || selectedIntent == .webSearch else { return false }
        return frame.object != nil || frame.source != nil || frame.contextReference != nil ||
            [.open, .call, .message, .create, .set, .enable, .disable, .scan, .recognize, .share, .navigate]
                .contains(where: { frame.action == $0 })
    }

    private func failClosedIntent(for frame: CanonicalSemanticFrame) -> CommandIntent {
        if frame.action == .open || frame.object == .app { return .open }
        if frame.action == .call || frame.object == .contact { return .contactLookup }
        if frame.action == .message { return .messageCompose }
        if frame.object == .photo { return .photoSearch }
        if frame.object == .file || frame.object == .document { return .fileSearch }
        if frame.object == .calendar { return .calendarQuery }
        if frame.object == .reminder { return .reminderQuery }
        if frame.object == .settings { return .settings }
        return .deviceAction
    }

    private static let verifiedApplicationCandidates: [ScopedEntityCandidate<String>] =
        LaunchDeviceApplications.verified.map { descriptor in
            .init(
                value: descriptor.id,
                displayName: descriptor.id,
                aliases: descriptor.aliases.union([descriptor.id])
            )
        }

    private static let verifiedServiceCandidates: [ScopedEntityCandidate<String>] =
        MessengerKind.allCases.map { kind in
            .init(
                value: kind.rawValue,
                displayName: kind.rawValue,
                aliases: [kind.rawValue]
            )
        } + [
            .init(value: "email", displayName: "email", aliases: ["email", "mail", "пошта", "почта"])
        ]

    private static let verifiedCatalogCandidates = CanonicalCatalogEntityRegistry.candidates

    private static func commandLanguage(
        _ text: String,
        hypotheses: [String: Double]
    ) -> CommandLanguage {
        if text.range(of: "[іїєґ]", options: .regularExpression) != nil { return .uk }
        if text.range(of: "[ыэъё]", options: .regularExpression) != nil { return .ru }
        if let best = hypotheses.max(by: { $0.value < $1.value }), best.value >= 0.55 {
            switch best.key {
            case "uk": return .uk
            case "ru": return .ru
            case "en": return .en
            case "de": return .de
            case "fr": return .fr
            default: break
            }
        }
        return .automatic
    }

    private static func languageHypotheses(_ text: String) -> [String: Double] {
#if canImport(NaturalLanguage)
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.languageHypotheses(withMaximum: 4).reduce(into: [:]) {
            output, pair in output[pair.key.rawValue] = pair.value
        }
#else
        return [:]
#endif
    }
}
