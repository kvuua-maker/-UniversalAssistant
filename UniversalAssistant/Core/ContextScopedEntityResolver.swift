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

struct ContextScopedEntityResolver<Value: Equatable & Sendable>: Sendable {
    let candidates: [ScopedEntityCandidate<Value>]
    var directThreshold = 0.72
    var ambiguityThreshold = 0.48
    var requiredMargin = 0.12

    func resolve(_ transcript: String) -> ScopedEntityResolution<Value> {
        resolveWithEvidence(transcript).resolution
    }

    func resolveWithEvidence(_ transcript: String) -> ScopedEntityResolutionEvidence<Value> {
        let query = Self.normalize(transcript)
        guard !query.isEmpty else {
            return .init(resolution: .unresolved, bestScore: 0, confidenceMargin: 0, mechanism: .unresolved)
        }
        let exact = candidates.filter { candidate in
            candidate.aliases.union([candidate.displayName]).map(Self.normalize).contains(query)
        }
        if exact.count == 1, let value = exact.first?.value {
            return .init(resolution: .resolved(value), bestScore: 1, confidenceMargin: 1, mechanism: .exact)
        }
        if exact.count > 1 {
            return .init(resolution: .ambiguous(Self.names(exact)), bestScore: 1, confidenceMargin: 0, mechanism: .exact)
        }

        var ranked: [(candidate: ScopedEntityCandidate<Value>, score: Double, mechanism: ScopedEntityMatchMechanism)] = []
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
        let cutoff = max(ambiguityThreshold, best.score - 0.08)
        let choices: [ScopedEntityCandidate<Value>] = ranked.compactMap { entry in
            entry.score >= cutoff ? entry.candidate : nil
        }
        let resolution: ScopedEntityResolution<Value> = choices.isEmpty ? .unresolved : .ambiguous(Self.names(choices))
        return .init(resolution: resolution, bestScore: best.score, confidenceMargin: margin, mechanism: best.mechanism)
    }

    private static func bestScore(for candidate: ScopedEntityCandidate<Value>, query: String) -> (value: Double, mechanism: ScopedEntityMatchMechanism) {
        // When a registry supplies explicit aliases, those are the authoritative
        // fuzzy surface forms. Internal/display identifiers remain valid exact
        // matches, but must not make a different candidate look phonetically
        // close merely because its internal id shares a prefix.
        let surfaces = candidate.aliases.isEmpty ? [candidate.displayName] : Array(candidate.aliases)
        var output: (value: Double, mechanism: ScopedEntityMatchMechanism) = (0, .unresolved)
        for alias in surfaces {
            let value = evidenceScore(query, normalize(alias))
            if value.value > output.value { output = value }
        }
        return output
    }
    private static func names(_ values: [ScopedEntityCandidate<Value>]) -> [String] {
        Array(Set(values.map(\.displayName))).sorted()
    }
    private static func normalize(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().filter { $0.isLetter || $0.isNumber }
    }
    private static func evidenceScore(_ lhs: String, _ rhs: String) -> (value: Double, mechanism: ScopedEntityMatchMechanism) {
        let folded = similarity(lhs, rhs)
        var best = (folded, ScopedEntityMatchMechanism.folded)
        let leftTransliteration = transliteration(lhs), rightTransliteration = transliteration(rhs)
        let transliterated = similarity(leftTransliteration, rightTransliteration) * 0.98
        if transliterated > best.0 { best = (transliterated, .transliteration) }
        let morphology = similarity(morphologicalStem(leftTransliteration), morphologicalStem(rightTransliteration)) * 0.94
        if morphology > best.0 { best = (morphology, .morphology) }
        let phonetic = similarity(phoneticKey(leftTransliteration), phoneticKey(rightTransliteration)) * 0.92
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
        let suffixes = ["iami", "amy", "ovi", "evi", "iem", "ogo", "omu", "ami", "ями", "ами", "ові", "еві", "ого", "ому", "ою", "ею", "у", "ю", "і", "и", "а", "я"]
        guard let suffix = suffixes.first(where: { value.count - $0.count >= 3 && value.hasSuffix($0) }) else { return value }
        return String(value.dropLast(suffix.count))
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
