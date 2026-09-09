import Foundation

/// Proposition-level evidence for natural statements that do not begin with an
/// imperative. A capability is inferred only from a compatible combination of
/// modality, predicate, object/destination and modifiers. Individual tokens are
/// never authoritative by themselves.
struct CanonicalPropositionInference: Equatable, Sendable {
    let intent: CommandIntent
    let entities: [String: String]
    let confidence: Double
    let evidence: Set<String>
}

struct CanonicalPropositionAnalyzer: Sendable {
    private enum Concept: Hashable {
        case desireOrNeed
        case acquisition
        case consumption
        case movement
        case locationProximity
        case destinationMarker
        case temporalMarker
        case filler
    }

    func infer(
        document: LanguageUnderstandingDocument,
        frame: CanonicalSemanticFrame,
        currentIntent: CommandIntent,
        constraints: CommandConstraints
    ) -> CanonicalPropositionInference? {
        let concepts = document.tokens.map(concepts(for:))
        let flattened = concepts.reduce(into: Set<Concept>()) { $0.formUnion($1) }
        let hasModality = flattened.contains(.desireOrNeed)
        let hasProximity = frame.modifiers.contains("proximity") || flattened.contains(.locationProximity)
        let hasAcquisition = flattened.contains(.acquisition)
        let hasConsumption = flattened.contains(.consumption)
        let hasMovement = flattened.contains(.movement)
        let content = contentSubject(document.tokens, concepts: concepts)

        // A nearby place proposition requires both a location modifier and an
        // activity/need proposition. A bare unknown noun near "nearby" does not
        // become a place solely because of one keyword.
        if hasProximity,
           (hasConsumption || hasAcquisition || (hasModality && !content.isEmpty)),
           maySelect(.placeSearch, over: currentIntent) {
            var entities = ["near_current_location": "true"]
            entities["query"] = content.isEmpty ? document.originalText : content
            return .init(
                intent: .placeSearch,
                entities: entities,
                confidence: (hasModality && (hasConsumption || hasAcquisition)) ? 0.90 : 0.82,
                evidence: ["modality_or_activity", "proximity", "content_role"]
            )
        }

        // Natural need/desire + movement + an explicit destination phrase is a
        // navigation proposition. The extracted target remains typed and is
        // validated by the MapKit boundary; this layer does not geocode or act.
        if hasModality, hasMovement,
           let destination = destinationSubject(document.tokens, concepts: concepts),
           maySelect(.navigation, over: currentIntent) {
            return .init(
                intent: .navigation,
                entities: ["destination": destination],
                confidence: 0.88,
                evidence: ["need_modality", "movement_predicate", "destination_role"]
            )
        }

        // A non-local acquisition proposition with a concrete object or typed
        // commerce constraint is provider-neutral product discovery. Nearby
        // acquisition was handled above as a place/store search.
        if hasModality, hasAcquisition, !hasProximity,
           (!content.isEmpty || !constraints.hardConstraintKeys.isEmpty),
           maySelect(.productSearch, over: currentIntent) {
            return .init(
                intent: .productSearch,
                entities: content.isEmpty ? [:] : ["query": content],
                confidence: 0.84,
                evidence: ["need_modality", "acquisition_predicate", "content_role"]
            )
        }
        return nil
    }

    private func maySelect(_ proposed: CommandIntent, over current: CommandIntent) -> Bool {
        if current == proposed { return true }
        return [.unknown, .webSearch, .show, .productSearch, .fashionDiscovery, .groceryBasket]
            .contains(current)
    }

    private func concepts(for token: LanguageUnderstandingDocument.Token) -> Set<Concept> {
        let value = token.morphology
        var output = Set<Concept>()
        if matches(value, roots: ["хоч", "хот", "треб", "потріб", "нуж", "необхід", "need", "want", "would", "like"]) {
            output.insert(.desireOrNeed)
        }
        if matches(value, roots: ["куп", "придба", "замов", "покуп", "закаж", "shop", "buy", "purchase", "order"]) {
            output.insert(.acquisition)
        }
        if matches(value, roots: ["вип", "попит", "поїст", "перекус", "їст", "есть", "вып", "drink", "eat", "dine"]) {
            output.insert(.consumption)
        }
        if matches(value, roots: ["діст", "потрап", "опин", "прибу", "їх", "йт", "добрат", "попаст", "ехать", "идт", "reach", "arrive", "get"]) {
            output.insert(.movement)
        }
        if matches(value, roots: ["поруч", "поблиз", "неподал", "поряд", "рядом", "ближай", "near", "nearby", "closest"]) {
            output.insert(.locationProximity)
        }
        if ["до", "на", "біля", "в", "у", "к", "to", "toward", "near"].contains(token.normalized) {
            output.insert(.destinationMarker)
        }
        if ["о", "об", "at", "через", "in"].contains(token.normalized) {
            output.insert(.temporalMarker)
        }
        if matches(value, roots: ["мен", "мне", "десь", "гдето", "будь", "б", "би", "please", "somewhere"]) {
            output.insert(.filler)
        }
        return output
    }

    private func matches(_ value: String, roots: [String]) -> Bool {
        roots.contains { value.hasPrefix($0) }
    }

    private func contentSubject(
        _ tokens: [LanguageUnderstandingDocument.Token],
        concepts: [Set<Concept>]
    ) -> String {
        zip(tokens, concepts).compactMap { token, roles in
            let excluded: Set<Concept> = [
                .desireOrNeed, .acquisition, .consumption, .movement,
                .locationProximity, .destinationMarker, .temporalMarker, .filler
            ]
            guard roles.isDisjoint(with: excluded), !token.normalized.allSatisfy(\.isNumber) else { return nil }
            return token.surface
        }.joined(separator: " ")
    }

    private func destinationSubject(
        _ tokens: [LanguageUnderstandingDocument.Token],
        concepts: [Set<Concept>]
    ) -> String? {
        guard let marker = concepts.indices.first(where: { concepts[$0].contains(.destinationMarker) }),
              marker + 1 < tokens.count else { return nil }
        let suffix = zip(tokens[(marker + 1)...], concepts[(marker + 1)...])
            .prefix { _, roles in !roles.contains(.temporalMarker) }
            .map { $0.0.surface }
        let value = suffix.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return value.isEmpty ? nil : value
    }
}
