import Foundation

struct CurrentContext: Equatable, Sendable {
    private(set) var lastResults: [String] = []
    private(set) var selectedResult: String?
    private(set) var expiresAt: Date?
    mutating func store(results: [String], now: Date = .now, lifetime: TimeInterval = 300) {
        lastResults = Array(results.prefix(5)); selectedResult = nil; expiresAt = now.addingTimeInterval(lifetime)
    }
    mutating func resolve(_ command: StructuredCommand, now: Date = .now) -> String? {
        guard let expiresAt, expiresAt > now, command.intent == .contextualSelection,
              let ordinal = command.constraints.ordinal, lastResults.indices.contains(ordinal - 1) else { return nil }
        selectedResult = lastResults[ordinal - 1]; return selectedResult
    }
    mutating func reset() { lastResults = []; selectedResult = nil; expiresAt = nil }
}
