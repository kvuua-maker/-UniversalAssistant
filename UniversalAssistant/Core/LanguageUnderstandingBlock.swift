import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

struct LanguageUnderstandingDocument: Equatable, Sendable {
    struct Token: Equatable, Sendable {
        let surface: String
        let normalized: String
        let morphology: String
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

/// The single semantic entry point for typed text, final Speech transcripts,
/// App Intent parameters, and compound subcommands in the shipped graph.
///
/// LocalCommandEngine is retained only as a compatibility candidate generator
/// while the 96 families migrate. It cannot bypass structural framing,
/// confidence decisions, or protected-domain web isolation.
struct LanguageUnderstandingBlock: EvidenceAwareCommandParsing, Sendable {
    private let legacyCandidate: LocalCommandEngine
    private let analyzer: CanonicalSemanticFrameAnalyzer
    private let applicationCandidates: [ScopedEntityCandidate<String>]
    private let serviceCandidates: [ScopedEntityCandidate<String>]
    private let catalogCandidates: [ScopedEntityCandidate<CanonicalCatalogEntity>]

    init(
        legacyCandidate: LocalCommandEngine = .init(),
        analyzer: CanonicalSemanticFrameAnalyzer = .init(),
        applicationCandidates: [ScopedEntityCandidate<String>]? = nil,
        serviceCandidates: [ScopedEntityCandidate<String>]? = nil,
        catalogCandidates: [ScopedEntityCandidate<CanonicalCatalogEntity>]? = nil
    ) {
        self.legacyCandidate = legacyCandidate
        self.analyzer = analyzer
        self.applicationCandidates = applicationCandidates ?? Self.verifiedApplicationCandidates
        self.serviceCandidates = serviceCandidates ?? Self.verifiedServiceCandidates
        self.catalogCandidates = catalogCandidates ?? Self.verifiedCatalogCandidates
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

        let frameResult = analyzer.analyze(original: text, normalized: document.normalizedText)
        var entities = legacy.entities
        var constraints = legacy.constraints
        for (key, value) in frameResult.entities { entities[key] = value }
        entities["language_understanding_version"] = "1"
        entities["semantic_confidence"] = String(format: "%.3f", frameResult.frame.confidence)

        var intent: CommandIntent
        if LocalUtilityEngine.canExecute(document.normalizedText) {
            intent = .localUtility
        } else if LocalUtilityEngine.recognizesCurrency(document.normalizedText) {
            intent = .currencyConversion
        } else if let structural = frameResult.intent {
            intent = structural
        } else {
            intent = legacy.intent
        }

        var needsClarification = legacy.needsClarification || entities["clarification_options"] != nil
        if let recovered = recoverApplication(frame: frameResult.frame, document: document) {
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
            switch recovered.resolution {
            case let .resolved(identifier):
                entities[serviceKey] = identifier
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

        if let recovered = recoverCatalog(
            document: document,
            intent: intent,
            constraints: constraints
        ) {
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

        if shouldFailClosed(frame: frameResult.frame, selectedIntent: intent) {
            intent = failClosedIntent(for: frameResult.frame)
            needsClarification = true
        }
        if [.contactLookup, .contactCall].contains(intent),
           entities["contact"] == nil, entities["phone_number"] == nil {
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
            risk: legacy.risk,
            needsClarification: needsClarification || intent == .unknown
        )
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
                let folded = surface.precomposedStringWithCompatibilityMapping
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "uk_UA"))
                    .lowercased()
                return LanguageUnderstandingDocument.Token(
                    surface: surface,
                    normalized: folded,
                    morphology: morphology(folded)
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

    private func recoverApplication(
        frame: CanonicalSemanticFrame,
        document: LanguageUnderstandingDocument
    ) -> ScopedEntityResolutionEvidence<String>? {
        guard isApplicationLaunch(frame) else { return nil }
        let actionMorphology: Set<String> = [
            "відкр", "откр", "open", "launch", "запуст", "перейд",
            "програм", "застос", "прилож", "app"
        ]
        let subject = document.tokens
            .filter { token in
                !actionMorphology.contains(where: { token.morphology.hasPrefix($0) })
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
        let markerIndex = normalized.indices.first { strongMarkers.contains(normalized[$0]) }
            ?? normalized.indices.first { weakMarkers.contains(normalized[$0]) }
        guard let markerIndex, markerIndex + 1 < document.tokens.count else { return nil }
        let subject = document.tokens[(markerIndex + 1)...].map(\.surface).joined(separator: " ")
        let evidence = ContextScopedEntityResolver(candidates: serviceCandidates).resolveWithEvidence(subject)
        let strongScope = strongMarkers.contains(normalized[markerIndex])
        if !strongScope, case .unresolved = evidence.resolution { return nil }
        return evidence
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
            !ignoredMorphology.contains(where: { token.morphology.hasPrefix($0) }) &&
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

    private static let verifiedCatalogCandidates: [ScopedEntityCandidate<CanonicalCatalogEntity>] =
        UkrainianRetailerRegistry.records.map { record in
            let entity = CanonicalCatalogEntity(
                id: record.id,
                displayName: record.displayName,
                kind: .retailer
            )
            return .init(value: entity, displayName: record.displayName, aliases: [record.displayName, record.id])
        }

    private static func morphology(_ token: String) -> String {
        let suffixes = [
            "ями", "ами", "ові", "еві", "ого", "ому", "ою", "ею",
            "ів", "ов", "ам", "ям", "ах", "ях", "у", "ю", "і", "и", "а", "я"
        ]
        guard let suffix = suffixes.first(where: {
            token.count - $0.count >= 3 && token.hasSuffix($0)
        }) else { return token }
        return String(token.dropLast(suffix.count))
    }

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
