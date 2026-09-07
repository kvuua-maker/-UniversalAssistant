import Foundation

enum ResultFactState: String, Codable, Sendable { case verified, unknown, unavailable }
struct ResultFact: Identifiable, Equatable, Codable, Sendable {
    let id: String; let label: String; let value: String?; let state: ResultFactState
    let source: String?; let observedAt: Date?; let priority: Int
}
enum ResultActionKind: String, Codable, Sendable { case open, navigate, purchaseHandoff, retry, clarify, showMore, showPhoto }
struct ResultAction: Identifiable, Equatable, Codable, Sendable {
    let id: String; let title: String; let kind: ResultActionKind; let destination: URL?
}
struct DeterministicResult: Equatable, Codable, Sendable {
    let primaryAnswer: String
    let facts: [ResultFact]
    let actions: [ResultAction]
    let warnings: [String]
    let aiInvocationCount: Int
}

enum ResultComposerError: Error, Equatable { case invalidPrimaryAnswer, unverifiedValue, invalidAction }

struct DeterministicResultComposer: Sendable {
    func compose(primaryAnswer: String, facts: [ResultFact], actions: [ResultAction] = [], warnings: [String] = []) throws -> DeterministicResult {
        let answer = primaryAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { throw ResultComposerError.invalidPrimaryAnswer }
        guard facts.allSatisfy({ fact in
            switch fact.state {
            case .verified: return fact.value?.isEmpty == false && fact.source?.isEmpty == false && fact.observedAt != nil
            case .unknown, .unavailable: return fact.value == nil
            }
        }) else { throw ResultComposerError.unverifiedValue }
        guard actions.allSatisfy({ $0.kind == .clarify || $0.kind == .retry || $0.kind == .showMore || $0.kind == .showPhoto || $0.destination?.scheme != nil }) else {
            throw ResultComposerError.invalidAction
        }
        let ordered = facts.enumerated().sorted {
            $0.element.priority == $1.element.priority ? $0.offset < $1.offset : $0.element.priority > $1.element.priority
        }.map(\.element)
        return .init(primaryAnswer: answer, facts: ordered, actions: actions, warnings: warnings, aiInvocationCount: 0)
    }
}
