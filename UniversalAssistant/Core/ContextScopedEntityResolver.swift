import Foundation

/// Resolves a noisy transcript only inside an authoritative semantic domain.
/// Candidates must come from a verified registry, Contacts, provider output,
/// or CurrentContext; the resolver never manufactures an entity.
struct ScopedEntityCandidate<Value: Equatable & Sendable>: Equatable, Sendable {
    let value: Value
    let displayName: String
    let aliases: Set<String>
}

enum ScopedEntityResolution<Value: Equatable & Sendable>: Equatable, Sendable {
    case resolved(Value)
    case ambiguous([String])
    case unresolved
}

enum ScopedEntityMatchMechanism: String, Equatable, Sendable {
    case exact, folded, transliteration, phonetic, morphology, unresolved
}

struct ScopedEntityResolutionEvidence<Value: Equatable & Sendable>: Equatable, Sendable {
    let resolution: ScopedEntityResolution<Value>
    let bestScore: Double
    let confidenceMargin: Double
    let mechanism: ScopedEntityMatchMechanism
}

extension ScopedEntityResolutionEvidence {
    var isResolved: Bool {
        if case .resolved = resolution { return true }
        return false
    }
}

struct ContextScopedEntityResolver<Value: Equatable & Sendable>: Sendable {
    let candidates: [ScopedEntityCandidate<Value>]
    var directThreshold = 0.72
    var ambiguityThreshold = 0.48
    var requiredMargin = 0.12

    func resolve(_ transcript: String) -> ScopedEntityResolution<Value> {
        resolveWithEvidence(transcript).resolution
    }

    func resolveWithEvidence(_ transcript: String) -> ScopedEntityResolutionEvidence<Value> {
        let query = CanonicalMorphology.comparableText(transcript)
        guard !query.isEmpty else {
            return .init(resolution: .unresolved, bestScore: 0, confidenceMargin: 0, mechanism: .unresolved)
        }
        let exact = candidates.filter { candidate in
            candidate.aliases.union([candidate.displayName]).map(CanonicalMorphology.comparableText).contains(query)
        }
        if exact.count == 1, let value = exact.first?.value {
            return .init(resolution: .resolved(value), bestScore: 1, confidenceMargin: 1, mechanism: .exact)
        }
        if exact.count > 1 {
            return .init(resolution: .ambiguous(Self.names(exact)), bestScore: 1, confidenceMargin: 0, mechanism: .exact)
        }

        var ranked: [(candidate: ScopedEntityCandidate<Value>, score: Double, mechanism: ScopedEntityMatchMechanism)] = []
        let morphological = candidates.filter { candidate in
            candidate.aliases.union([candidate.displayName]).contains {
                Self.sameMorphologicalPhrase(transcript, $0)
            }
        }
        if morphological.count == 1, let value = morphological.first?.value {
            return .init(resolution: .resolved(value), bestScore: 0.96, confidenceMargin: 0.96, mechanism: .morphology)
        }
        if morphological.count > 1 {
            return .init(resolution: .ambiguous(Self.names(morphological)), bestScore: 0.96, confidenceMargin: 0, mechanism: .morphology)
        }

        for candidate in candidates {
            let score = Self.bestScore(for: candidate, query: query)
            ranked.append((candidate, score.value, score.mechanism))
        }
        ranked.sort { lhs, rhs in
            lhs.score == rhs.score ? lhs.candidate.displayName < rhs.candidate.displayName : lhs.score > rhs.score
        }
        guard let best = ranked.first, best.score >= ambiguityThreshold else {
            return .init(resolution: .unresolved, bestScore: ranked.first?.score ?? 0, confidenceMargin: 0, mechanism: .unresolved)
        }
        let runnerUp = ranked.dropFirst().first?.score ?? 0
        let margin = best.score - runnerUp
        if best.score >= directThreshold, margin >= requiredMargin {
            return .init(resolution: .resolved(best.candidate.value), bestScore: best.score, confidenceMargin: margin, mechanism: best.mechanism)
        }
        let cutoff = max(ambiguityThreshold, best.score - requiredMargin)
        let choices: [ScopedEntityCandidate<Value>] = ranked.compactMap { entry in
            entry.score >= cutoff ? entry.candidate : nil
        }
        // A weak unique match is not a real ambiguity and must not suggest an
        // invented entity. Only two or more plausible candidates are rendered
        // as choices; otherwise the role remains unresolved/fail-closed.
        let resolution: ScopedEntityResolution<Value> = choices.count >= 2
            ? .ambiguous(Self.names(choices))
            : .unresolved
        return .init(resolution: resolution, bestScore: best.score, confidenceMargin: margin, mechanism: best.mechanism)
    }

    private static func bestScore(for candidate: ScopedEntityCandidate<Value>, query: String) -> (value: Double, mechanism: ScopedEntityMatchMechanism) {
        var output = evidenceScore(query, CanonicalMorphology.comparableText(candidate.displayName))
        for alias in candidate.aliases {
            let value = evidenceScore(query, CanonicalMorphology.comparableText(alias))
            if value.value > output.value { output = value }
        }
        return output
    }
    private static func names(_ values: [ScopedEntityCandidate<Value>]) -> [String] {
        Array(Set(values.map(\.displayName))).sorted()
    }
    private static func sameMorphologicalPhrase(_ lhs: String, _ rhs: String) -> Bool {
        let left = tokenForms(lhs)
        let right = tokenForms(rhs)
        guard !left.isEmpty, left.count == right.count else { return false }
        return zip(left, right).allSatisfy { lhsForms, rhsForms in
            !lhsForms.filter({ $0.count >= 3 }).isDisjoint(with: rhsForms.filter({ $0.count >= 3 }))
        }
    }

    private static func tokenForms(_ value: String) -> [Set<String>] {
        value.split { !$0.isLetter && !$0.isNumber }.map {
            CanonicalMorphology.forms(for: String($0))
        }

    }
    private static func evidenceScore(_ lhs: String, _ rhs: String) -> (value: Double, mechanism: ScopedEntityMatchMechanism) {
        let folded = similarity(lhs, rhs)
        var best = (folded, ScopedEntityMatchMechanism.folded)
        let leftTransliteration = transliteration(lhs), rightTransliteration = transliteration(rhs)
        let transliterated = similarity(leftTransliteration, rightTransliteration) * 0.98
        if transliterated > best.0 { best = (transliterated, .transliteration) }
        let morphology = similarity(morphologicalStem(leftTransliteration), morphologicalStem(rightTransliteration)) * 0.94
        if morphology > best.0 { best = (morphology, .morphology) }
        let phonetic = phoneticSimilarity(phoneticKey(leftTransliteration), phoneticKey(rightTransliteration)) * 0.92
        if phonetic > best.0 { best = (phonetic, .phonetic) }
        return best
    }
    /// Character-based Ukrainian/Russian-to-Latin folding for comparison only.
    /// It contains no entity substitutions.
    private static func transliteration(_ value: String) -> String {
        let table: [Character: String] = [
            "а":"a", "б":"b", "в":"v", "г":"h", "ґ":"g", "д":"d", "е":"e", "є":"ie", "ё":"io",
            "ж":"zh", "з":"z", "и":"y", "і":"i", "ї":"i", "й":"i", "к":"k", "л":"l", "м":"m",
            "н":"n", "о":"o", "п":"p", "р":"r", "с":"s", "т":"t", "у":"u", "ф":"f", "х":"kh",
            "ц":"ts", "ч":"ch", "ш":"sh", "щ":"shch", "ы":"y", "э":"e", "ю":"iu", "я":"ia",
            "ь":"", "ъ":""
        ]
        return value.reduce(into: "") { output, character in output += table[character] ?? String(character) }
    }
    /// General phoneme-family key for realistic Speech substitutions and clipped
    /// endings. It never maps a noisy token to a named entity.
    private static func phoneticKey(_ value: String) -> String {
        var output = value
            .replacingOccurrences(of: "shch", with: "sh")
            .replacingOccurrences(of: "sch", with: "sh")
            .replacingOccurrences(of: "wh", with: "v")
            .replacingOccurrences(of: "w", with: "v")
            .replacingOccurrences(of: "ph", with: "f")
            .replacingOccurrences(of: "ck", with: "k")
            .replacingOccurrences(of: "qu", with: "k")
            .replacingOccurrences(of: "q", with: "k")
            .replacingOccurrences(of: "x", with: "ks")
            .replacingOccurrences(of: "z", with: "s")
        output.removeAll { "aeiouy'’`- _".contains($0) }
        return output.reduce(into: "") { result, character in
            if result.last != character { result.append(character) }
        }
    }
    private static func morphologicalStem(_ value: String) -> String {
        // evidenceScore operates on the transliterated representation, so the
        // inflection rules here must be transliterated too. These are reusable
        // Ukrainian/Russian case endings, not named-entity substitutions.
        let suffixes = [
            "iamy", "iami", "amy", "ami", "ovi", "evi", "iem", "em",
            "ogo", "omu", "oiu", "eiu", "akh", "iakh", "ykh", "ikh",
            "u", "iu", "i", "y", "a", "ia", "o", "e"
        ]
        guard let suffix = suffixes.first(where: { value.count - $0.count >= 3 && value.hasSuffix($0) }) else { return value }
        return String(value.dropLast(suffix.count))
    }
    private static func phoneticSimilarity(_ lhs: String, _ rhs: String) -> Double {
        // A one-consonant key is not identity evidence. Two or more ordered
        // consonants can support a clipped spoken query inside a bounded domain.
        // Keep this evidence directional: a long unrelated input must never
        // collapse into a short candidate merely because its consonants happen to occur in order.
        let base = similarity(lhs, rhs)
        guard lhs.count >= 2, rhs.count >= 2, lhs.count <= rhs.count else { return base }
        var searchStart = rhs.startIndex
        let isOrderedSubsequence = lhs.allSatisfy { character in
            guard let index = rhs[searchStart...].firstIndex(of: character) else { return false }
            searchStart = rhs.index(after: index)
            return true
        }
        if isOrderedSubsequence {
            let coverage = Double(lhs.count) / Double(rhs.count)
            return max(base, 0.75 + 0.20 * coverage)
        }
        guard rhs.hasPrefix(lhs) else { return base }
        // Speech commonly clips a final syllable. Inside an already-authoritative
        // entity domain, a three-consonant prefix is useful evidence, but direct
        // execution still requires the resolver's runner-up confidence margin.
        let coverage = Double(lhs.count) / Double(rhs.count)
        return max(base, 0.78 + 0.16 * coverage)
    }
    private static func similarity(_ lhs: String, _ rhs: String) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        if lhs == rhs { return 1 }
        if min(lhs.count, rhs.count) >= 4, (lhs.hasPrefix(rhs) || rhs.hasPrefix(lhs)) {
            return Double(min(lhs.count, rhs.count)) / Double(max(lhs.count, rhs.count)) * 0.16 + 0.76
        }
        let left = Array(lhs), right = Array(rhs)
        var previous = Array(0...right.count)
        for (i, l) in left.enumerated() {
            var current = [i + 1]
            for (j, r) in right.enumerated() {
                current.append(min(current[j] + 1, previous[j + 1] + 1, previous[j] + (l == r ? 0 : 1)))
            }
            previous = current
        }
        return 1 - Double(previous[right.count]) / Double(max(left.count, right.count))
    }
}
