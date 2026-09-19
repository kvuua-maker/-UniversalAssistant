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
        for (key, value) in frameResult.entities { entities[key] = value }
        entities["language_understanding_version"] = "1"
        entities["semantic_confidence"] = String(format: "%.3f", frameResult.frame.confidence)

        var intent: CommandIntent
        if LocalUtilityEngine.canExecute(document.normalizedText) {
            intent = .localUtility
        } else if LocalUtilityEngine.recognizesCurrency(document.normalizedText) {
            intent = .currencyConversion
        } else if [.emergency, .multiStep, .shoppingList].contains(legacy.intent) {
            // These families are recognized from complete command structure.
            // A frame describing one clause (for example CALL inside an
            // emergency request or SCAN inside a scan-then-translate request)
            // must not replace the authoritative whole-command intent.
            intent = legacy.intent
        } else if let structural = frameResult.intent {
            intent = structural
        } else {
            intent = legacy.intent
        }

        var constraints = legacy.constraints
        var needsClarification = legacy.needsClarification || entities["clarification_options"] != nil
        if shouldRecoverApplication(frame: frameResult.frame, resolvedIntent: frameResult.intent),
           let recovered = recoverApplication(frame: frameResult.frame, document: document) {
            switch recovered.resolution {
            case let .resolved(identifier):
                entities["app"] = identifier
                entities["entity_match_mechanism"] = recovered.mechanism.rawValue
                entities["entity_match_confidence"] = String(format: "%.3f", recovered.bestScore)
                if isApplicationLaunch(frameResult.frame) { intent = .open }
                needsClarification = false
            case let .ambiguous(options):
                entities["clarification_options"] = options.joined(separator: "|")
                intent = .open
                needsClarification = true
            case .unresolved:
                if isApplicationLaunch(frameResult.frame) {
                    intent = .open
                    needsClarification = true
                }
            }
        }

        if let recovered = recoverService(frame: frameResult.frame, document: document),
           frameResult.frame.service == nil {
            switch recovered.resolution {
            case let .resolved(service):
                let key = intent == .contactCall ? "call_service" : "message_service"
                entities[key] = service
                entities["service_match_mechanism"] = recovered.mechanism.rawValue
                entities["service_match_confidence"] = String(format: "%.3f", recovered.bestScore)
                needsClarification = false
            case let .ambiguous(options):
                entities["clarification_options"] = options.joined(separator: "|")
                needsClarification = true
            case .unresolved:
                needsClarification = true
            }
        }

        if let recovered = recoverCatalog(intent: intent, document: document) {
            switch recovered.resolution {
            case let .resolved(entity):
                switch entity.kind {
                case .brand:
                    entities["brand"] = entity.displayName
                    constraints.brand = entity.displayName
                    constraints.hardConstraintKeys.insert("brand")
                case .product:
                    entities["product_entity_id"] = entity.id
                    entities["product"] = entity.displayName
                case .provider, .retailer:
                    entities["provider_id"] = entity.id
                    entities["retailer"] = entity.displayName
                }
                entities["catalog_match_mechanism"] = recovered.mechanism.rawValue
                entities["catalog_match_confidence"] = String(format: "%.3f", recovered.bestScore)
            case let .ambiguous(options):
                // Low-score collisions in a broad configured catalog are not
                // evidence that the user named any catalog entity. Clarify only
                // when the utterance is itself a strong match to that domain.
                if recovered.bestScore >= 0.72 {
                    entities["clarification_options"] = options.joined(separator: "|")
                    needsClarification = true
                }
            case .unresolved: break
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
            "brand", "product", "provider_id", "retailer", "location",
            "destination", "query", "source_text", "target_language"
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

    /// Application-name recovery is only allowed when application launch is
    /// still the unresolved semantic role. A leading OPEN must not steal a
    /// resolved Clipboard, Settings, Find My, Files, or other system action.
    private func shouldRecoverApplication(
        frame: CanonicalSemanticFrame,
        resolvedIntent: CommandIntent?
    ) -> Bool {
        guard isApplicationLaunch(frame) else { return false }
        return frame.object == .app || frame.app != nil || resolvedIntent == nil || resolvedIntent == .open
    }

    private func recoverService(
        frame: CanonicalSemanticFrame,
        document: LanguageUnderstandingDocument
    ) -> ScopedEntityResolutionEvidence<String>? {
        guard frame.action == .call || frame.action == .message || frame.action == .share else { return nil }
        let markers = [" через ", " via ", " using ", " каналом ", " сервісом ", " сервисом ", " у застосунку ", " в приложении "]
        guard let marker = markers.compactMap({ value in
            document.originalText.range(of: value, options: [.caseInsensitive, .diacriticInsensitive])
        }).min(by: { $0.lowerBound < $1.lowerBound }) else { return nil }
        let subject = String(document.originalText[marker.upperBound...])
        return bestScopedResolution(in: subject, candidates: serviceCandidates)
    }

    private func recoverCatalog(
        intent: CommandIntent,
        document: LanguageUnderstandingDocument
    ) -> ScopedEntityResolutionEvidence<CanonicalCatalogEntity>? {
        guard [.productSearch, .fashionDiscovery, .groceryBasket].contains(intent),
              !catalogCandidates.isEmpty else { return nil }
        return bestScopedResolution(in: document.originalText, candidates: catalogCandidates)
    }

    /// Compare bounded token windows only inside a typed entity domain. This
    /// tolerates surrounding natural language without letting an entity name
    /// select the capability or compete with candidates from another domain.
    private func bestScopedResolution<Value: Equatable & Sendable>(
        in text: String,
        candidates: [ScopedEntityCandidate<Value>]
    ) -> ScopedEntityResolutionEvidence<Value> {
        let tokens = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        var subjects = [text]
        for length in 1...min(3, tokens.count) {
            for start in 0...(tokens.count - length) {
                subjects.append(tokens[start..<(start + length)].joined(separator: " "))
            }
        }
        let resolver = ContextScopedEntityResolver(candidates: candidates)
        return subjects.map(resolver.resolveWithEvidence)
            .max { lhs, rhs in
                if lhs.bestScore == rhs.bestScore { return lhs.confidenceMargin < rhs.confidenceMargin }
                return lhs.bestScore < rhs.bestScore
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

    private static let verifiedServiceCandidates: [ScopedEntityCandidate<String>] = {
        let verifiedApps = Dictionary(
            uniqueKeysWithValues: LaunchDeviceApplications.verified.map { ($0.id, $0) }
        )
        return MessengerKind.allCases.map { kind in
            let aliases = verifiedApps[kind.rawValue]?.aliases ?? []
            return .init(
                value: kind.rawValue,
                displayName: kind.rawValue,
                aliases: aliases.union([kind.rawValue])
            )
        } + [
            .init(value: "email", displayName: "email", aliases: ["email", "mail", "пошта", "почта"])
        ]
    }()

    private static let verifiedCatalogCandidates: [ScopedEntityCandidate<CanonicalCatalogEntity>] =
        UkrainianRetailerRegistry.records.map { record in
            let entity = CanonicalCatalogEntity(id: record.id, displayName: record.displayName, kind: .retailer)
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
