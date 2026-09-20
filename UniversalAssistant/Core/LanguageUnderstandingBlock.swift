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
        "Baldinini", "Nike", "Adidas", "Puma", "Zara", "Mango", "Gucci", "Pierre Cardin", "Prada"
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
        let providers = OfficialPublicProviderHandoffRegistry.records.map { record in
            let entity = CanonicalCatalogEntity(
                id: record.id,
                displayName: record.displayName,
                kind: record.domain == .grocery ? .retailer : .provider
            )
            return ScopedEntityCandidate(
                value: entity,
                displayName: record.displayName,
                aliases: record.aliases.union([record.displayName, record.id])
            )
        }
        return brands + providers
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
        .init(domain: "jobs", intent: .productSearch,
              objectRoots: ["робот", "ваканс", "працевлаштуван", "работ", "ваканс", "job", "vacanc", "employment"],
              actionRoots: ["знайд", "покаж", "підбер", "шукай", "найд", "покаж", "find", "show", "search", "list"],
              minimumObjectMatches: 1),
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
        .init(domain: "transport_tickets", intent: .ticketSearch,
              objectRoots: ["поїзд", "потяг", "залізниц", "вокзал", "розклад", "поезд", "железнодорож", "вокзал", "расписан", "train", "rail", "timetable", "schedule"],
              actionRoots: ["знайд", "покаж", "куп", "перевір", "найд", "find", "show", "buy", "check"],
              minimumObjectMatches: 2),
        .init(domain: "tickets", intent: .ticketSearch,
              objectRoots: ["квит", "білет", "ticket", "fare", "поді", "событ", "event", "концерт", "вистав", "театр", "стендап", "шоу", "мюзикл", "дитяч", "фестивал", "цирк", "спорт", "матч", "турнір", "кіно", "сеанс", "concert", "theatre", "show", "festival", "circus", "sport", "cinema", "movie", "match", "tournament"],
              actionRoots: ["знайд", "підбер", "покаж", "куп", "найд", "find", "search", "show", "buy"],
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
        let providerNounCollision = currentIntent == .messageCompose && frame.action == .query
        let publicEventCollision = currentIntent == .calendarQuery && document.tokens.contains { token in
            token.morphologyForms.contains { form in
                ["квит", "білет", "ticket", "fare", "концерт", "театр", "стендап", "шоу", "фестивал", "цирк", "матч", "турнір", "cinema", "movie"].contains {
                    form.hasPrefix($0)
                }
            }
        }
        guard externalIntents.contains(currentIntent) || unresolvedIntents.contains(currentIntent) || providerNounCollision || publicEventCollision else {
            return nil
        }
        guard frame.person == nil, frame.contextReference == nil else { return nil }
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

        // A room is a lodging object only when accompanied by an occupancy
        // role and a discovery/booking action. This keeps bare phone/room
        // numbers out of lodging while recovering structurally complete hotel
        // requests that do not literally say "hotel".
        let hasRoom = !matchedRoots(["номер", "кімнат", "комнат", "room"]).isEmpty
        let hasOccupancy = !matchedRoots(["гост", "люд", "особ", "чоловік", "человек", "guest", "people", "person"]).isEmpty
        let hasLodgingGoal = !matchedRoots(["знайд", "підбер", "покаж", "заброн", "найд", "find", "search", "show", "book"]).isEmpty
        if hasRoom, hasOccupancy, hasLodgingGoal {
            return .init(
                intent: .hotelSearch, domain: "lodging", confidence: 0.90,
                evidence: matchedRoots(["номер", "кімнат", "комнат", "room", "гост", "люд", "особ", "guest", "people"])
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
/// Canonical lexical extraction is an internal evidence stage. It cannot
/// bypass structural framing, confidence decisions, or protected-domain web
/// isolation, and it is not a competing production parser.
struct LanguageUnderstandingBlock: EvidenceAwareCommandParsing, Sendable {
    private let lexicalCandidate: CanonicalLexicalCandidateExtractor
    private let analyzer: CanonicalSemanticFrameAnalyzer
    private let propositionAnalyzer: CanonicalPropositionAnalyzer
    private let applicationCandidates: [ScopedEntityCandidate<String>]
    private let serviceCandidates: [ScopedEntityCandidate<String>]
    private let catalogCandidates: [ScopedEntityCandidate<CanonicalCatalogEntity>]

    init(
        lexicalCandidate: CanonicalLexicalCandidateExtractor = .init(),
        analyzer: CanonicalSemanticFrameAnalyzer = .init(),
        propositionAnalyzer: CanonicalPropositionAnalyzer = .init(),
        applicationCandidates: [ScopedEntityCandidate<String>]? = nil,
        serviceCandidates: [ScopedEntityCandidate<String>]? = nil,
        catalogCandidates: [ScopedEntityCandidate<CanonicalCatalogEntity>]? = nil
    ) {
        self.lexicalCandidate = lexicalCandidate
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
        let alternatives = uniqueSpeechHypotheses(
            speechEvidence.alternativeTranscripts + speechEvidence.segmentAlternativeTranscripts,
            excluding: text,
            limit: VoiceRecognitionCandidateBuilder.maximumWholeTranscriptions +
                VoiceRecognitionCandidateBuilder.maximumSegmentTranscriptions
        )
        var selected = primary
        var selectedAlternative = false
        for alternative in alternatives {
            let candidate = parseAuthoritative(alternative)
            if shouldAdopt(candidate, over: selected) {
                selected = candidate
                selectedAlternative = true
            }
        }
        selected = applyingCanonicalSpeechEntityEvidence(
            authoritativeHypotheses: [text] + alternatives,
            partialHypotheses: speechEvidence.partialTranscriptHistory,
            to: selected
        )
        var entities = selected.entities
        entities["speech_alternative_count"] = String(alternatives.count)
        entities["speech_partial_history_count"] = String(speechEvidence.partialTranscriptHistory.count)
        if let confidence = speechEvidence.averageSegmentConfidence {
            entities["speech_mean_confidence"] = String(format: "%.3f", confidence)
        }
        if selectedAlternative { entities["speech_selected_alternative"] = "true" }
        return CanonicalCurrentCommandRoleNormalizer.apply(to: .init(
            id: primary.id,
            originalText: text,
            normalizedText: selected.normalizedText,
            language: selected.language,
            intent: selected.intent,
            entities: entities,
            constraints: selected.constraints,
            risk: selected.risk,
            needsClarification: selected.needsClarification
        ))
    }

    private func uniqueSpeechHypotheses(
        _ values: [String],
        excluding primary: String,
        limit: Int
    ) -> [String] {
        guard limit > 0 else { return [] }
        var seen = Set([CanonicalMorphology.comparableText(primary)])
        return values.compactMap { value -> String? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = CanonicalMorphology.comparableText(trimmed)
            guard !trimmed.isEmpty, !key.isEmpty, seen.insert(key).inserted else { return nil }
            return trimmed
        }.prefix(limit).map { $0 }
    }

    /// Partial Speech hypotheses are not authoritative command text. They may
    /// contribute only one unambiguous canonical entity already present in a
    /// legitimate registry, while action, free-form query and all other roles
    /// remain owned by the final transcript.
    private func applyingCanonicalSpeechEntityEvidence(
        authoritativeHypotheses: [String],
        partialHypotheses: [String],
        to command: StructuredCommand
    ) -> StructuredCommand {
        let hypotheses = uniqueSpeechHypotheses(
            authoritativeHypotheses + partialHypotheses,
            excluding: "",
            limit: VoiceRecognitionCandidateBuilder.maximumWholeTranscriptions +
                VoiceRecognitionCandidateBuilder.maximumSegmentTranscriptions +
                VoiceRecognitionCandidateBuilder.maximumPartialHistory + 1
        )
        let candidates = hypotheses.map(parseAuthoritative)
        var entities = command.entities
        var constraints = command.constraints
        var intent = command.intent
        var needsClarification = command.needsClarification
        var applied = false

        if let service = canonicalSpeechServiceHit(
            authoritativeHypotheses: authoritativeHypotheses,
            partialHypotheses: partialHypotheses,
            intent: intent
        ),
           let key = serviceKey(for: intent),
           entities[key] == nil || entities["service_resolution"] == "canonical_default" || entities[key] == service.value {
            entities[key] = service.value
            entities["service_match_resolution"] = "resolved"
            entities["service_match_mechanism"] = service.evidence.mechanism.rawValue
            entities["service_match_confidence"] = String(format: "%.3f", service.evidence.bestScore)
            entities["service_match_margin"] = String(format: "%.3f", service.evidence.confidenceMargin)
            entities["service_resolution"] = "speech_canonical_registry"
            entities["speech_entity_evidence"] = "canonical_service"
            entities.removeValue(forKey: "clarification_options")
            entities.removeValue(forKey: "clarification_role")
            needsClarification = false
            applied = true
        }

        let catalogCandidates = candidates.filter { $0.entities["catalog_entity_id"] != nil }
        let catalogIDs = Set(catalogCandidates.compactMap { $0.entities["catalog_entity_id"] })
        if catalogIDs.count == 1,
           let catalogID = catalogIDs.first,
           command.entities["catalog_entity_id"].map({ $0 == catalogID }) != false,
           let evidence = catalogCandidates.max(by: {
               speechEntityEvidenceScore($0, prefix: "catalog_match") <
                   speechEntityEvidenceScore($1, prefix: "catalog_match")
           }),
           speechEntityEvidenceScore(evidence, prefix: "catalog_match") >= 0.72,
           let canonical = catalogCandidatesForSpeechEvidence.first(where: { $0.value.id == catalogID })?.value {
            for key in evidence.entities.keys where key.hasPrefix("catalog_match_") {
                entities[key] = evidence.entities[key]
            }
            entities["catalog_entity_id"] = catalogID
            entities[canonical.kind.rawValue] = canonical.displayName
            entities["speech_entity_evidence"] = "canonical_catalog"
            switch canonical.kind {
            case .brand:
                constraints.brand = canonical.displayName
                constraints.hardConstraintKeys.insert("brand")
            case .product:
                break
            case .provider, .retailer:
                entities["provider_domain"] = evidence.entities["provider_domain"] ?? entities["provider_domain"]
                entities["provider_boundary"] = evidence.entities["provider_boundary"] ?? entities["provider_boundary"]
            }
            if (intent == .unknown || intent == .webSearch || needsClarification),
               evidence.intent != .unknown, evidence.intent != .webSearch {
                intent = evidence.intent
                needsClarification = evidence.needsClarification
                entities.removeValue(forKey: "clarification_options")
                entities.removeValue(forKey: "clarification_role")
            }
            if entities["query"] == nil { entities["query"] = evidence.entities["query"] }
            applied = true
        }

        // A final/alternative Apple transcription can preserve the acoustic
        // shape of a proper noun without preserving its spelling (and a partial
        // can preserve a name later omitted from the final). Resolve that text
        // directly against the same bounded canonical registry used by the
        // ordinary parser. This is registry- and intent-scoped: it cannot
        // manufacture an entity, cannot cross into personal/system actions,
        // and conflicting Apple hypotheses remain unresolved.
        if let hit = canonicalSpeechCatalogHit(
            authoritativeHypotheses: uniqueSpeechHypotheses(
                authoritativeHypotheses,
                excluding: "",
                limit: VoiceRecognitionCandidateBuilder.maximumWholeTranscriptions +
                    VoiceRecognitionCandidateBuilder.maximumSegmentTranscriptions + 1
            ),
            partialHypotheses: uniqueSpeechHypotheses(
                partialHypotheses,
                excluding: "",
                limit: VoiceRecognitionCandidateBuilder.maximumPartialHistory
            ),
            intent: intent
        ) {
            let currentScore = Double(entities["catalog_match_confidence"] ?? "") ?? 0
            let currentID = entities["catalog_entity_id"]
            let mayReplaceCurrent = currentID == nil || currentID == hit.canonical.id ||
                hit.evidence.bestScore - currentScore >= 0.08 ||
                (hit.roleScoped && hit.evidence.bestScore >= currentScore - 0.02)
            if mayReplaceCurrent {
                entities["catalog_entity_id"] = hit.canonical.id
                entities[hit.canonical.kind.rawValue] = hit.canonical.displayName
                entities["catalog_match_resolution"] = "resolved"
                entities["catalog_match_mechanism"] = hit.evidence.mechanism.rawValue
                entities["catalog_match_confidence"] = String(format: "%.3f", hit.evidence.bestScore)
                entities["catalog_match_margin"] = String(format: "%.3f", hit.evidence.confidenceMargin)
                entities["speech_entity_evidence"] = "canonical_catalog"
                switch hit.canonical.kind {
                case .brand:
                    constraints.brand = hit.canonical.displayName
                    constraints.hardConstraintKeys.insert("brand")
                    if intent == .unknown || intent == .webSearch {
                        intent = .productSearch
                        needsClarification = false
                    }
                case .product:
                    entities["product"] = hit.canonical.displayName
                case .provider, .retailer:
                    if let provider = OfficialPublicProviderHandoffRegistry.records.first(where: {
                        $0.id == hit.canonical.id
                    }) {
                        entities["provider_domain"] = providerDomain(provider.domain)
                        entities["provider_boundary"] = "explicit_official_provider"
                        if intent == .unknown || intent == .webSearch || needsClarification {
                            intent = providerIntent(provider.domain)
                            needsClarification = false
                            entities.removeValue(forKey: "clarification_options")
                            entities.removeValue(forKey: "clarification_role")
                        }
                    }
                }
                applied = true
            }
        }

        let applicationCandidates = candidates.filter {
            $0.intent == .open && $0.entities["app"] != nil
        }
        let applicationIDs = Set(applicationCandidates.compactMap { $0.entities["app"] })
        if applicationIDs.count == 1,
           let applicationID = applicationIDs.first,
           command.entities["app"].map({ $0 == applicationID }) != false,
           (intent == .open || intent == .unknown),
           let evidence = applicationCandidates.max(by: {
               speechEntityEvidenceScore($0, prefix: "entity_match") <
                   speechEntityEvidenceScore($1, prefix: "entity_match")
           }),
           speechEntityEvidenceScore(evidence, prefix: "entity_match") >= 0.72 {
            entities["app"] = applicationID
            for key in evidence.entities.keys where key.hasPrefix("entity_match_") {
                entities[key] = evidence.entities[key]
            }
            entities["speech_entity_evidence"] = "canonical_application"
            entities.removeValue(forKey: "clarification_options")
            entities.removeValue(forKey: "clarification_role")
            intent = .open
            needsClarification = false
            applied = true
        }

        if !applied { return command }
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

    private func speechEntityEvidenceScore(_ command: StructuredCommand, prefix: String) -> Double {
        Double(command.entities["\(prefix)_confidence"] ?? "") ?? 0
    }

    private struct CanonicalSpeechCatalogHit {
        let canonical: CanonicalCatalogEntity
        let evidence: ScopedEntityResolutionEvidence<CanonicalCatalogEntity>
        let roleScoped: Bool
    }

    private struct CanonicalSpeechServiceHit {
        let value: String
        let evidence: ScopedEntityResolutionEvidence<String>
    }

    /// Recovers only a channel/service occupying an explicit typed service
    /// span. Candidates remain bounded to the canonical service registry and
    /// final/Apple alternatives take precedence over partial history.
    private func canonicalSpeechServiceHit(
        authoritativeHypotheses: [String],
        partialHypotheses: [String],
        intent: CommandIntent
    ) -> CanonicalSpeechServiceHit? {
        guard serviceKey(for: intent) != nil else { return nil }
        let markers: Set<String> = [
            "через", "via", "using", "канал", "channel", "сервіс", "сервис",
            "service", "месенджер", "мессенджер", "messenger", "у", "в", "по"
        ]

        func bestHit(in hypotheses: [String]) -> CanonicalSpeechServiceHit? {
            var hits: [CanonicalSpeechServiceHit] = []
            for hypothesis in hypotheses {
                let tokens = Self.document(hypothesis).tokens
                for marker in tokens.indices where markers.contains(tokens[marker].normalized) {
                    let start = marker + 1
                    guard start < tokens.count else { continue }
                    for length in 1...min(3, tokens.count - start) {
                        let subject = tokens[start..<(start + length)].map(\.surface).joined(separator: " ")
                        let evidence = ContextScopedEntityResolver(candidates: serviceCandidates)
                            .resolveWithEvidence(subject)
                        guard case let .resolved(value) = evidence.resolution else { continue }
                        hits.append(.init(value: value, evidence: evidence))
                    }
                }
            }
            let ranked = hits.sorted {
                if $0.evidence.bestScore == $1.evidence.bestScore {
                    return $0.evidence.confidenceMargin > $1.evidence.confidenceMargin
                }
                return $0.evidence.bestScore > $1.evidence.bestScore
            }
            guard let best = ranked.first else { return nil }
            let competing = ranked.first { $0.value != best.value }
            guard best.evidence.bestScore - (competing?.evidence.bestScore ?? 0) >= 0.12 else { return nil }
            return best
        }

        return bestHit(in: authoritativeHypotheses) ?? bestHit(in: partialHypotheses)
    }

    private func canonicalSpeechCatalogHit(
        authoritativeHypotheses: [String],
        partialHypotheses: [String],
        intent: CommandIntent
    ) -> CanonicalSpeechCatalogHit? {
        let permittedIntents: Set<CommandIntent> = [
            .unknown, .webSearch, .productSearch, .fashionDiscovery, .groceryBasket,
            .serviceSearch, .restaurantSearch, .reservation, .taxiSearch, .taxiCompare,
            .publicTransport, .ticketSearch, .ticketPurchaseHandoff, .hotelSearch,
            .travelPlan, .parcelTrack, .multiStep
        ]
        guard permittedIntents.contains(intent) else { return nil }

        func bestHit(in hypotheses: [String]) -> CanonicalSpeechCatalogHit? {
            var bestByID: [String: CanonicalSpeechCatalogHit] = [:]
            for hypothesis in hypotheses {
                let document = Self.document(hypothesis)
                let scoped = speechCatalogCandidates(for: intent, hypothesis: hypothesis)
                guard !scoped.isEmpty else { continue }
                let roleEvidence = providerRoleEvidence(in: document.tokens, candidates: scoped)
                let evidence = roleEvidence ?? bestScopedResolution(in: document.tokens, candidates: scoped)
                guard case let .resolved(canonical) = evidence.resolution,
                      evidence.bestScore >= 0.72 else { continue }
                let hit = CanonicalSpeechCatalogHit(
                    canonical: canonical,
                    evidence: evidence,
                    roleScoped: roleEvidence != nil
                )
                let previous = bestByID[canonical.id]
                if evidence.bestScore > (previous?.evidence.bestScore ?? 0) ||
                    (evidence.bestScore == previous?.evidence.bestScore &&
                     hit.roleScoped && previous?.roleScoped == false) {
                    bestByID[canonical.id] = hit
                }
            }
            let ranked = bestByID.values.sorted {
                if $0.evidence.bestScore == $1.evidence.bestScore {
                    return $0.canonical.id < $1.canonical.id
                }
                return $0.evidence.bestScore > $1.evidence.bestScore
            }
            guard let best = ranked.first else { return nil }
            let competingScore = ranked.dropFirst().first?.evidence.bestScore ?? 0
            guard best.evidence.bestScore - competingScore >= 0.12 else { return nil }
            return best
        }
        // Final and Apple alternative transcriptions are authoritative.
        // Partial history is recovery evidence only when that tier contains no
        // safe canonical entity, so an early unstable partial cannot veto a
        // complete final provider/service role.
        return bestHit(in: authoritativeHypotheses) ?? bestHit(in: partialHypotheses)
    }

    private func speechCatalogCandidates(
        for intent: CommandIntent,
        hypothesis: String
    ) -> [ScopedEntityCandidate<CanonicalCatalogEntity>] {
        let document = Self.document(hypothesis)
        let frameResult = analyzer.analyze(
            original: hypothesis,
            normalized: document.normalizedText,
            morphologyForms: document.tokens.map(\.morphologyForms)
        )
        let inferenceIntent: CommandIntent = intent == .multiStep ? .unknown : intent
        let inferred = CanonicalExternalProviderBoundaryAnalyzer.infer(
            document: document,
            frame: frameResult.frame,
            currentIntent: inferenceIntent
        )
        let inferredDomain: OfficialPublicProviderDomain? = switch inferred?.domain {
        case "grocery_delivery": .grocery
        case "lodging": .lodging
        case "car_rental": .carRental
        case "transport_tickets": .transport
        case "tickets": .events
        case "jobs": .jobs
        case "parcel_tracking": .parcel
        default: nil
        }
        let intentDomain: OfficialPublicProviderDomain? = switch intent {
        case .groceryBasket: .grocery
        case .hotelSearch: .lodging
        case .taxiSearch, .taxiCompare: .carRental
        case .publicTransport: .transport
        case .ticketSearch, .ticketPurchaseHandoff: nil
        case .parcelTrack: .parcel
        default: nil
        }
        let domain = inferredDomain ?? intentDomain
        let tokenComparable: (String) -> String = { value in
            value.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map { CanonicalMorphology.comparableText(String($0)) }
                .filter { !$0.isEmpty }.joined(separator: " ")
        }
        let comparableHypothesis = " " + tokenComparable(hypothesis) + " "
        let exactProviders = catalogCandidates.filter { candidate in
            guard candidate.value.kind == .provider || candidate.value.kind == .retailer else { return false }
            return candidate.aliases.union([candidate.displayName]).contains { alias in
                let value = tokenComparable(alias)
                return !value.isEmpty && comparableHypothesis.contains(" \(value) ")
            }
        }
        if !exactProviders.isEmpty { return exactProviders }
        if let domain {
            let domains: Set<OfficialPublicProviderDomain> = inferred?.domain == "tickets"
                ? [.events, .cinema]
                : [domain]
            return catalogCandidates.filter { candidate in
                guard candidate.value.kind == .provider || candidate.value.kind == .retailer else {
                    return false
                }
                return OfficialPublicProviderHandoffRegistry.records.contains {
                    $0.id == candidate.value.id && domains.contains($0.domain)
                }
            }
        }
        if intent == .ticketSearch || intent == .ticketPurchaseHandoff {
            let domains: Set<OfficialPublicProviderDomain> = [.events, .cinema, .transport]
            return catalogCandidates.filter { candidate in
                OfficialPublicProviderHandoffRegistry.records.contains {
                    $0.id == candidate.value.id && domains.contains($0.domain)
                }
            }
        }
        // A mixed global pool can turn arbitrary speech into the nearest
        // retailer, parcel carrier, job source, or brand. Without an already
        // established compatible domain, fuzzy catalog promotion is forbidden.
        let providerMarkers: Set<String> = [
            "на", "у", "в", "через", "від", "from", "on", "at", "via",
            "маркетплейс", "магазин", "сайт", "marketplace", "store", "site"
        ]
        let hasScopedProviderRole = document.tokens.contains { providerMarkers.contains($0.normalized) }
        switch intent {
        case .productSearch, .fashionDiscovery:
            return catalogCandidates.filter { candidate in
                if candidate.value.kind == .brand || candidate.value.kind == .product { return true }
                guard hasScopedProviderRole else { return false }
                return OfficialPublicProviderHandoffRegistry.records.contains {
                    $0.id == candidate.value.id && [.marketplace, .grocery].contains($0.domain)
                }
            }
        case .groceryBasket:
            return catalogCandidates.filter { candidate in
                if candidate.value.kind == .product { return true }
                guard candidate.value.kind == .provider || candidate.value.kind == .retailer else { return false }
                return OfficialPublicProviderHandoffRegistry.records.contains {
                    $0.id == candidate.value.id && $0.domain == .grocery
                }
            }
        default:
            return []
        }
    }

    /// Resolve only the typed provider/service slot immediately following a
    /// scope preposition. This prevents a product word later in the sentence
    /// from stealing provider identity while remaining language- and
    /// registry-generic.
    private func providerRoleEvidence(
        in tokens: [LanguageUnderstandingDocument.Token],
        candidates: [ScopedEntityCandidate<CanonicalCatalogEntity>]
    ) -> ScopedEntityResolutionEvidence<CanonicalCatalogEntity>? {
        let markers: Set<String> = [
            "на", "у", "в", "через", "від", "from", "on", "at", "via",
            "маркетплейс", "магазин", "сайт", "marketplace", "store", "site"
        ]
        var evidence: [ScopedEntityResolutionEvidence<CanonicalCatalogEntity>] = []
        for marker in tokens.indices where markers.contains(tokens[marker].normalized) {
            let start = marker + 1
            guard start < tokens.count else { continue }
            for length in 1...min(4, tokens.count - start) {
                let surface = tokens[start..<(start + length)].map(\.surface).joined(separator: " ")
                let candidate = ContextScopedEntityResolver(candidates: candidates).resolveWithEvidence(surface)
                if candidate.isResolved { evidence.append(candidate) }
            }
        }
        return evidence.max {
            if $0.bestScore == $1.bestScore { return $0.confidenceMargin < $1.confidenceMargin }
            return $0.bestScore < $1.bestScore
        }
    }

    private var catalogCandidatesForSpeechEvidence: [ScopedEntityCandidate<CanonicalCatalogEntity>] {
        catalogCandidates
    }

    private func parseAuthoritative(_ text: String) -> StructuredCommand {
        let document = Self.document(text)
        guard !document.normalizedText.isEmpty else {
            return .init(originalText: text, normalizedText: "", language: document.language, intent: .unknown, needsClarification: true)
        }

        let legacy = lexicalCandidate.parse(text)
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
        let currency = FXConversionRequestParser().parse(document.normalizedText)
        let translation = CanonicalTranslationRoles.analyze(text)
        if let arithmetic {
            entities["arithmetic_confidence"] = String(format: "%.3f", arithmetic.confidence)
            entities["arithmetic_evidence"] = arithmetic.evidence.sorted().joined(separator: "|")
            entities["arithmetic_step_count"] = String(arithmetic.steps.count)
        }
        var intent: CommandIntent
        if LocalUtilityEngine.canExecute(document.normalizedText),
           arithmetic != nil || !hasIncompatibleStructuredUtilityObject(frameResult.frame) {
            intent = .localUtility
        } else if currency != nil || LocalUtilityEngine.recognizesCurrency(document.normalizedText) {
            intent = .currencyConversion
        } else if let translation {
            intent = .translation
            entities["source_text"] = translation.sourceText
            entities["target_language"] = translation.targetLanguage
            entities["semantic_evidence"] = "typed_translation_roles"
        } else if legacy.intent == .multiStep,
                  frameResult.frame.compound != nil || isRoutineDefinition(document.normalizedText) {
            // The lexical evidence stage has already required every separated clause to
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
            if entities["location"] == nil,
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

        var needsClarification = (proposition == nil && frameResult.intent == nil && legacy.needsClarification) ||
            entities["clarification_options"] != nil
        if emergencyTarget != nil || providerInference != nil || translation != nil { needsClarification = false }
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

        // A verified channel inside an explicit communication proposition is
        // stronger typed evidence than an object token that happens to look
        // like a device setting. Resolve the bounded SERVICE domain before the
        // selected capability can keep such a lexical collision.
        let structuralCommunicationIntent: CommandIntent? = switch frameResult.frame.action {
        case .call: .contactCall
        case .message, .share: .messageCompose
        default: nil
        }
        if emergencyTarget == nil,
           let structuralCommunicationIntent,
           intent != structuralCommunicationIntent,
           let serviceKey = serviceKey(for: structuralCommunicationIntent),
           entities[serviceKey] == nil,
           let recovered = recoverService(
               frame: frameResult.frame,
               document: document,
               intent: structuralCommunicationIntent
           ),
           case let .resolved(identifier) = recovered.resolution {
            intent = structuralCommunicationIntent
            recordResolutionEvidence(recovered, prefix: "service_match", entities: &entities)
            entities[serviceKey] = identifier
            entities["service_match_mechanism"] = recovered.mechanism.rawValue
            entities["service_match_confidence"] = String(format: "%.3f", recovered.bestScore)
            if structuralCommunicationIntent == .messageCompose {
                entities["recipient"] = communicationRecipient(
                    in: document,
                    excludingResolvedService: identifier
                ) ?? entities["recipient"].flatMap {
                    communicationRecipient($0, excludingResolvedService: identifier)
                }
            }
            if entities[structuralCommunicationIntent == .contactCall ? "contact" : "recipient"] != nil {
                needsClarification = false
            }
        }

        if let serviceKey = serviceKey(for: intent),
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
            constraints: constraints,
            frame: frameResult.frame,
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
                if let provider = OfficialPublicProviderHandoffRegistry.records.first(where: { $0.id == candidate.id }),
                   isProviderScopedCommerceRequest(document: document, frame: frameResult.frame) {
                    intent = providerIntent(provider.domain)
                    entities["provider_domain"] = providerDomain(provider.domain)
                    if let query = providerScopedQuery(document: document, provider: provider), !query.isEmpty {
                        entities["query"] = query
                        if provider.domain == .marketplace || provider.domain == .grocery {
                            entities["product"] = query
                        }
                    }
                    entities["provider_boundary"] = "explicit_official_provider"
                    entities.removeValue(forKey: "clarification_options")
                    entities.removeValue(forKey: "clarification_role")
                    needsClarification = false
                } else if (candidate.kind == .brand || candidate.kind == .product),
                          intent == .unknown || intent == .webSearch {
                    intent = .productSearch
                    needsClarification = false
                }
            case let .ambiguous(options):
                if providerInference == nil || isProviderScopedCommerceRequest(document: document, frame: frameResult.frame) {
                    entities["clarification_options"] = options.joined(separator: "|")
                    entities["clarification_role"] = "catalog"
                    needsClarification = true
                }
            case .unresolved:
                break
            }
        }

        // A terse catalogue request may legitimately omit an imperative
        // (for example, OBJECT + canonical BRAND). Classify that typed role
        // combination as product discovery without memorizing any command.
        if (intent == .unknown || intent == .webSearch),
           let brand = constraints.brand.flatMap({ catalogBrand(named: $0) }) ?? exactCatalogBrand(in: document),
           hasPhysicalProductObject(in: document) {
            intent = .productSearch
            entities["brand"] = brand.displayName
            entities["catalog_entity_id"] = brand.id
            entities["provider_domain"] = "product_catalog"
            entities["query"] = text
            entities["semantic_evidence"] = "typed_product_object_and_canonical_brand"
            constraints.brand = brand.displayName
            constraints.hardConstraintKeys.insert("brand")
            entities.removeValue(forKey: "clarification_options")
            entities.removeValue(forKey: "clarification_role")
            needsClarification = false
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

        if intent == .unknown,
           isGeneralInformationRequest(document: document, frame: frameResult.frame) {
            intent = .webSearch
            entities["query"] = text
            entities["semantic_evidence"] = "typed_general_information"
            needsClarification = false
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
        let parsed = StructuredCommand(
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
        return CanonicalDomainIntegrityPolicy.apply(
            to: CanonicalCurrentCommandRoleNormalizer.apply(to: parsed)
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
        guard candidate.intent != .unknown, candidate.intent != .webSearch else { return false }
        if candidate.intent != primary.intent {
            // A complete typed utility/translation structure is stronger than
            // a noun collision in the recognizer's primary hypothesis. Other
            // cross-family alternatives remain fail-closed.
            let structurallyComplete = switch candidate.intent {
            case .localUtility:
                CanonicalArithmeticExpressionAnalyzer.analyze(candidate.normalizedText) != nil
            case .currencyConversion:
                FXConversionRequestParser().parse(candidate.normalizedText) != nil
            case .translation:
                candidate.entities["source_text"] != nil && candidate.entities["target_language"] != nil
            default:
                false
            }
            guard structurallyComplete else {
                if primary.needsClarification,
                   primary.entities["clarification_role"] == "catalog",
                   candidate.entities["catalog_entity_id"] != nil,
                   candidate.entities["catalog_match_mechanism"] == "exact",
                   candidate.entities["provider_boundary"] == "explicit_official_provider" {
                    return true
                }
                return primary.needsClarification && candidate.intent == .open &&
                    candidate.entities["app"] != nil
            }
            return true
        }
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
        let subjectTokens = document.tokens
            .filter { token in
                token.morphologyForms.allSatisfy { form in
                    !exactActionTokens.contains(form) &&
                        !actionMorphologyRoots.contains(where: form.hasPrefix)
                }
            }
        guard !subjectTokens.isEmpty else {
            return .init(
                resolution: .unresolved,
                bestScore: 0,
                confidenceMargin: 0,
                mechanism: .unresolved
            )
        }
        return bestScopedResolution(in: subjectTokens, candidates: applicationCandidates)
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

        // Without an explicit channel marker, arbitrary PERSON or message-body
        // tokens are not SERVICE evidence. Exact canonical channel names were
        // already resolved by CanonicalSemanticFrameAnalyzer; fuzzy recovery is
        // restricted to the marked span above.
        return nil
    }

    private func isGeneralInformationRequest(
        document: LanguageUnderstandingDocument,
        frame: CanonicalSemanticFrame
    ) -> Bool {
        guard frame.object == nil,
              frame.person == nil,
              frame.service == nil,
              frame.app == nil,
              frame.source == nil,
              frame.contextReference == nil else { return false }
        let forms = document.tokens.reduce(into: Set<String>()) { result, token in
            result.insert(token.normalized)
            result.formUnion(token.morphologyForms)
        }
        let informationActions = [
            "розкаж", "дізнай", "поясн", "перевір", "уточн",
            "tell", "explain", "describe", "check", "query"
        ]
        let informationObjects = [
            "новин", "котирув", "акці", "факт", "відомост", "інформац", "стан",
            "news", "quote", "stock", "fact", "information", "status"
        ]
        let actionEvidence = frame.action == .query || forms.contains { value in
            informationActions.contains { value.hasPrefix($0) }
        }
        let objectEvidence = forms.contains { value in
            informationObjects.contains { value.hasPrefix($0) }
        }
        let informationObjectAction = objectEvidence && frame.action.map {
            [.show, .search, .query].contains($0)
        } == true
        return informationObjectAction || (actionEvidence && (objectEvidence || document.tokens.count >= 4))
    }

    private func isRoutineDefinition(_ normalized: String) -> Bool {
        ["коли я кажу", "когда я говорю", "when i say", "wenn ich", "quand je dis"]
            .contains(where: normalized.contains)
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

    private func communicationRecipient(
        in document: LanguageUnderstandingDocument,
        excludingResolvedService service: String
    ) -> String? {
        guard let candidate = serviceCandidates.first(where: { $0.value == service }) else { return nil }
        let resolver = ContextScopedEntityResolver(candidates: [candidate])
        var bestSpan: Range<Int>?
        var bestScore = 0.0
        let markers: Set<String> = ["через", "via", "using", "у", "в", "по", "канал", "каналом"]
        let normalized = document.tokens.map { CanonicalMorphology.comparableText($0.surface) }

        // A channel introduced by a semantic marker owns the longest bounded
        // resolved prefix after that marker. This removes every token of a
        // split/clipped service name without consuming the recipient before it.
        if let marker = normalized.indices.first(where: { markers.contains(normalized[$0]) }),
           marker + 1 < document.tokens.count {
            let maximumLength = min(3, document.tokens.count - marker - 1)
            for length in stride(from: maximumLength, through: 1, by: -1) {
                let span = (marker + 1)..<(marker + 1 + length)
                let subject = document.tokens[span].map(\.surface).joined(separator: " ")
                let evidence = resolver.resolveWithEvidence(subject)
                if case .resolved = evidence.resolution {
                    bestSpan = span
                    bestScore = evidence.bestScore
                    break
                }
            }
        }

        if bestSpan == nil {
            for length in 1...min(3, document.tokens.count) {
                for start in 0...(document.tokens.count - length) {
                    let subject = document.tokens[start..<(start + length)].map(\.surface).joined(separator: " ")
                    let evidence = resolver.resolveWithEvidence(subject)
                    guard case .resolved = evidence.resolution, evidence.bestScore > bestScore else { continue }
                    bestSpan = start..<(start + length)
                    bestScore = evidence.bestScore
                }
            }
        }
        guard let bestSpan else { return nil }
        var surfaces = document.tokens.map(\.surface)
        surfaces.removeSubrange(bestSpan)
        if bestSpan.lowerBound > 0, surfaces.indices.contains(bestSpan.lowerBound - 1),
           markers.contains(CanonicalMorphology.comparableText(surfaces[bestSpan.lowerBound - 1])) {
            surfaces.remove(at: bestSpan.lowerBound - 1)
        }
        let command = surfaces.joined(separator: " ")
        return CanonicalMessageRoleAnalyzer.analyze(command)?.recipient
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
        constraints: CommandConstraints,
        frame: CanonicalSemanticFrame,
    ) -> ScopedEntityResolutionEvidence<CanonicalCatalogEntity>? {
        let catalogFamily = [.productSearch, .fashionDiscovery, .groceryBasket].contains(intent)
        let providerBackedFamily: Set<CommandIntent> = [
            .productSearch, .fashionDiscovery, .groceryBasket, .serviceSearch,
            .restaurantSearch, .reservation, .taxiSearch, .taxiCompare,
            .publicTransport, .ticketSearch, .ticketPurchaseHandoff,
            .hotelSearch, .travelPlan, .parcelTrack
        ]
        let unresolvedProviderRequest = intent == .unknown || intent == .webSearch
        let explicitProviderScope = isProviderScopedCommerceRequest(document: document, frame: frame)
        let providerCandidates = catalogCandidates.filter {
            $0.value.kind == .provider || $0.value.kind == .retailer
        }
        guard providerBackedFamily.contains(intent) || unresolvedProviderRequest || explicitProviderScope else { return nil }
        let comparable: (String) -> String = { value in
            value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
        }
        let normalizedText = " \(comparable(document.originalText)) "
        let exactProviders = providerCandidates.filter { candidate in
            candidate.aliases.union([candidate.displayName]).contains { alias in
                let value = comparable(alias)
                return !value.isEmpty && normalizedText.contains(" \(value) ")
            }
        }
        if !exactProviders.isEmpty {
            if exactProviders.count == 1, let only = exactProviders.first {
                return ContextScopedEntityResolver(candidates: exactProviders)
                    .resolveWithEvidence(only.displayName)
            }
            return bestScopedResolution(in: document.tokens, candidates: exactProviders)
        }
        let providerMarkers: Set<String> = [
            "на", "у", "в", "через", "маркетплейс", "магазин", "сайт",
            "on", "at", "from", "via", "marketplace", "store", "site"
        ]
        if (providerBackedFamily.contains(intent) || unresolvedProviderRequest),
           let marker = document.tokens.indices.last(where: { providerMarkers.contains(document.tokens[$0].normalized) }),
           marker + 1 < document.tokens.count, !providerCandidates.isEmpty,
           !(Set(["у", "в", "на", "at"]).contains(document.tokens[marker].normalized) &&
             frame.location != nil &&
             providerCandidates.allSatisfy { candidate in
                 OfficialPublicProviderHandoffRegistry.records.contains { $0.id == candidate.value.id }
             }) {
            let markerCandidates = providerBackedFamily.contains(intent)
                ? providerCandidates.filter { candidate in
                    guard let provider = OfficialPublicProviderHandoffRegistry.records.first(where: { $0.id == candidate.value.id }) else { return true }
                    return providerIntent(provider.domain) == intent
                }
                : providerCandidates
            let evidence = bestScopedResolution(in: Array(document.tokens[(marker + 1)...]), candidates: markerCandidates)
            switch evidence.resolution {
            case .resolved, .ambiguous: return evidence
            case .unresolved: break
            }
        }
        if providerBackedFamily.contains(intent), !catalogFamily {
            let compatibleProviders = providerCandidates.filter { candidate in
                guard let provider = OfficialPublicProviderHandoffRegistry.records.first(where: { $0.id == candidate.value.id }) else { return true }
                return providerIntent(provider.domain) == intent
            }
            if !compatibleProviders.isEmpty {
                let evidence = bestScopedResolution(in: document.tokens, candidates: compatibleProviders)
                if evidence.mechanism == .exact || evidence.mechanism == .morphology {
                    switch evidence.resolution {
                    case .resolved, .ambiguous: return evidence
                    case .unresolved: break
                    }
                }
            }
        }
        guard catalogFamily else { return nil }
        let candidates = catalogCandidates.filter {
            $0.value.kind != .provider && $0.value.kind != .retailer
        }
        guard !candidates.isEmpty else { return nil }
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
        return bestScopedResolution(in: subjects, candidates: candidates)
    }

    private func exactCatalogBrand(in document: LanguageUnderstandingDocument) -> CanonicalCatalogEntity? {
        let text = " \(CanonicalMorphology.comparableText(document.originalText)) "
        return catalogCandidates.lazy
            .filter { $0.value.kind == .brand }
            .first { candidate in
                candidate.aliases.union([candidate.displayName]).contains { alias in
                    let value = CanonicalMorphology.comparableText(alias)
                    return !value.isEmpty && text.contains(" \(value) ")
                }
            }?.value
    }

    private func catalogBrand(named name: String) -> CanonicalCatalogEntity? {
        let expected = CanonicalMorphology.comparableText(name)
        return catalogCandidates.first { candidate in
            candidate.value.kind == .brand &&
                CanonicalMorphology.comparableText(candidate.displayName) == expected
        }?.value
    }

    private func hasPhysicalProductObject(in document: LanguageUnderstandingDocument) -> Bool {
        let roots = [
            "товар", "продукт", "взут", "черев", "кросів", "одяг", "сумк", "рюкзак",
            "ноутбук", "телефон", "мебл", "годин", "product", "item", "shoe", "boot",
            "clothing", "bag", "backpack", "laptop", "phone", "furniture", "watch"
        ]
        let tokenMatch = document.tokens.contains { token in
            ([token.normalized] + Array(token.morphologyForms)).contains { form in
                roots.contains(where: form.hasPrefix)
            }
        }
        if tokenMatch { return true }
        return CanonicalMorphology.comparableText(document.originalText)
            .split(separator: " ")
            .contains { token in roots.contains { token.hasPrefix($0) } }
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
        for length in 1...min(4, tokens.count) {
            for start in 0...(tokens.count - length) {
                subjects.append(tokens[start..<(start + length)].map(\.surface).joined(separator: " "))
            }
        }
        let evidence = subjects.map { resolver.resolveWithEvidence($0) }
        let strongest = evidence.max {
                if $0.bestScore == $1.bestScore { return $0.confidenceMargin < $1.confidenceMargin }
                return $0.bestScore < $1.bestScore
            }
        let strongestResolved = evidence.filter(\.isResolved).max {
            if $0.bestScore == $1.bestScore { return $0.confidenceMargin < $1.confidenceMargin }
            return $0.bestScore < $1.bestScore
        }
        // A generic one-token span can be exactly shared by several candidates
        // (for example a category word inside a multi-token proper noun). It
        // must not hide a nearly-as-strong unambiguous multi-token resolution.
        if let strongest, let strongestResolved,
           !strongest.isResolved,
           strongestResolved.bestScore >= 0.72,
           strongest.bestScore - strongestResolved.bestScore <= 0.08 {
            return strongestResolved
        }
        return strongest ?? .init(
            resolution: .unresolved,
            bestScore: 0,
            confidenceMargin: 0,
            mechanism: .unresolved
        )
    }

    private func isProviderScopedCommerceRequest(
        document: LanguageUnderstandingDocument,
        frame: CanonicalSemanticFrame
    ) -> Bool {
        let scopeMarkers: Set<String> = [
            "на", "у", "в", "через", "від", "from", "on", "at", "via",
            "маркетплейс", "магазин", "сайт", "marketplace", "store", "site"
        ]
        let actionRoots = [
            "знайд", "покаж", "пошук", "шукай", "порівн", "куп", "замов", "брон",
            "find", "show", "search", "compare", "buy", "order", "book", "track", "відстеж"
        ]
        let hasScope = document.tokens.contains { scopeMarkers.contains($0.normalized) }
        let hasAction = document.tokens.contains { token in
            token.morphologyForms.contains { form in actionRoots.contains(where: form.hasPrefix) }
        }
        guard hasScope && hasAction else { return false }
        guard frame.person == nil, frame.contextReference == nil else { return false }
        return ![.call, .message, .share, .navigate].contains(frame.action)
    }

    private func providerIntent(_ domain: OfficialPublicProviderDomain) -> CommandIntent {
        switch domain {
        case .marketplace: .productSearch
        case .grocery: .groceryBasket
        case .lodging: .hotelSearch
        case .carRental: .serviceSearch
        case .events, .cinema, .transport: .ticketSearch
        case .jobs: .productSearch
        case .parcel: .parcelTrack
        }
    }

    private func providerDomain(_ domain: OfficialPublicProviderDomain) -> String {
        switch domain {
        case .marketplace: "product_catalog"
        case .grocery: "grocery_delivery"
        case .lodging: "lodging"
        case .carRental: "car_rental"
        case .events, .cinema: "tickets"
        case .transport: "transport_tickets"
        case .jobs: "jobs"
        case .parcel: "parcel_tracking"
        }
    }

    private func providerScopedQuery(
        document: LanguageUnderstandingDocument,
        provider: OfficialPublicProviderHandoff
    ) -> String? {
        let providerForms = provider.aliases.union([provider.displayName]).map {
            CanonicalMorphology.comparableText($0)
        }
        let ignoredRoots = [
            "знайд", "покаж", "пошук", "шукай", "порівн", "куп", "замов", "брон",
            "find", "show", "search", "compare", "buy", "order", "book", "track", "відстеж"
        ]
        let ignoredTokens: Set<String> = [
            "на", "у", "в", "через", "від", "from", "on", "at", "via",
            "маркетплейс", "магазин", "сайт", "marketplace", "store", "site"
        ]
        var surfaces: [String] = []
        var index = 0
        while index < document.tokens.count {
            var matched = false
            for length in stride(from: min(4, document.tokens.count - index), through: 1, by: -1) {
                let value = CanonicalMorphology.comparableText(
                    document.tokens[index..<(index + length)].map(\.surface).joined(separator: " ")
                )
                if providerForms.contains(value) {
                    index += length
                    matched = true
                    break
                }
            }
            if matched { continue }
            let token = document.tokens[index]
            let isAction = token.morphologyForms.contains { form in
                ignoredRoots.contains(where: form.hasPrefix)
            }
            if !isAction && !ignoredTokens.contains(token.normalized) {
                surfaces.append(token.surface)
            }
            index += 1
        }
        let value = surfaces.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// “Start/launch” is structurally a set action for timers and alarms, but
    /// becomes an app launch only when no concrete device/personal object was
    /// identified. This keeps capability selection role-driven rather than
    /// depending on one spelling of an application command.
    private func isApplicationLaunch(_ frame: CanonicalSemanticFrame) -> Bool {
        frame.object == .app ||
            (frame.action == .open && (frame.object == nil || frame.object == .media)) ||
            (frame.action == .show && frame.app != nil) ||
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
        } + [
            // Recognition is separate from execution availability. iOS has no
            // public URL/API to launch Voice Memos or start its recording, but
            // the command must still resolve to a truthful system restriction.
            .init(value: "voice-memos", displayName: "Voice Memos",
                  aliases: CanonicalSpeechEntityRegistry.aliases(for: "voice-memos")),
            .init(value: "files", displayName: "Files", aliases: CanonicalSpeechEntityRegistry.aliases(for: "files")),
            .init(value: "camera", displayName: "Camera", aliases: CanonicalSpeechEntityRegistry.aliases(for: "camera")),
            .init(value: "calendar", displayName: "Calendar", aliases: CanonicalSpeechEntityRegistry.aliases(for: "calendar"))
        ]

    private static let verifiedServiceCandidates: [ScopedEntityCandidate<String>] =
        [
            // “повідомлення/message” describes the action/object, not an
            // explicitly selected provider. Unqualified messages default to
            // Apple Messages later in the typed semantic contract.
            .init(value: "messages", displayName: "messages", aliases: CanonicalSpeechEntityRegistry.communicationAliases["messages"]!),
            .init(value: "whatsapp", displayName: "whatsapp", aliases: CanonicalSpeechEntityRegistry.communicationAliases["whatsapp"]!),
            .init(value: "telegram", displayName: "telegram", aliases: CanonicalSpeechEntityRegistry.communicationAliases["telegram"]!),
            .init(value: "viber", displayName: "viber", aliases: CanonicalSpeechEntityRegistry.communicationAliases["viber"]!),
            .init(value: "signal", displayName: "signal", aliases: ["signal", "сигнал"]),
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
