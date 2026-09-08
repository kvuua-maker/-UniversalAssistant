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

struct ContextScopedEntityResolver<Value: Equatable & Sendable>: Sendable {
    let candidates: [ScopedEntityCandidate<Value>]
    var directThreshold = 0.72
    var ambiguityThreshold = 0.48
    var requiredMargin = 0.12

    func resolve(_ transcript: String) -> ScopedEntityResolution<Value> {
        let query = Self.normalize(transcript)
        guard !query.isEmpty else { return .unresolved }
        let exact = candidates.filter { candidate in
            candidate.aliases.union([candidate.displayName]).map(Self.normalize).contains(query)
        }
        if exact.count == 1, let value = exact.first?.value { return .resolved(value) }
        if exact.count > 1 { return .ambiguous(Self.names(exact)) }

        var ranked: [(candidate: ScopedEntityCandidate<Value>, score: Double)] = []
        for candidate in candidates {
            ranked.append((candidate, Self.bestScore(for: candidate, query: query)))
        }
        ranked.sort { lhs, rhs in
            lhs.score == rhs.score ? lhs.candidate.displayName < rhs.candidate.displayName : lhs.score > rhs.score
        }
        guard let best = ranked.first, best.score >= ambiguityThreshold else { return .unresolved }
        let runnerUp = ranked.dropFirst().first?.score ?? 0
        if best.score >= directThreshold, best.score - runnerUp >= requiredMargin { return .resolved(best.candidate.value) }
        let cutoff = max(ambiguityThreshold, best.score - 0.08)
        let choices: [ScopedEntityCandidate<Value>] = ranked.compactMap { entry in
            entry.score >= cutoff ? entry.candidate : nil
        }
        return choices.isEmpty ? .unresolved : .ambiguous(Self.names(choices))
    }

    private static func bestScore(for candidate: ScopedEntityCandidate<Value>, query: String) -> Double {
        var output = similarity(query, normalize(candidate.displayName))
        for alias in candidate.aliases { output = max(output, similarity(query, normalize(alias))) }
        return output
    }
    private static func names(_ values: [ScopedEntityCandidate<Value>]) -> [String] {
        Array(Set(values.map(\.displayName))).sorted()
    }
    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased().filter { $0.isLetter || $0.isNumber }
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
