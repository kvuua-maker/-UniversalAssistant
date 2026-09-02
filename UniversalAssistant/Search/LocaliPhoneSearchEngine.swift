import Foundation

enum LocalSearchSourceKind: String, Codable, CaseIterable, Sendable {
    case contacts, calendar, reminders, notes, shoppingLists, actionHistory, photos, files
}

enum LocalSearchAccess: Equatable, Sendable {
    case permitted
    case limited
    case permissionRequired
    case denied
    case unavailable
}

struct LocalSearchQuery: Equatable, Sendable {
    let text: String
    var dateRange: Range<Date>?
    var preferredSources: Set<LocalSearchSourceKind>
    var limit: Int

    init(text: String, dateRange: Range<Date>? = nil,
         preferredSources: Set<LocalSearchSourceKind> = [], limit: Int = 5) {
        self.text = text
        self.dateRange = dateRange
        self.preferredSources = preferredSources
        self.limit = max(1, min(limit, 10))
    }
}

struct LocalSearchResult: Identifiable, Equatable, Sendable {
    let id: String
    let source: LocalSearchSourceKind
    let title: String
    let subtitle: String?
    let occurredAt: Date?
    let exactNameMatch: Bool
    let relevance: Int
    let openReference: String
}

struct LocalSearchSourceResponse: Equatable, Sendable {
    let source: LocalSearchSourceKind
    let access: LocalSearchAccess
    let results: [LocalSearchResult]
}

protocol LocalSearchSource: Sendable {
    var kind: LocalSearchSourceKind { get }
    func search(_ query: LocalSearchQuery) async -> LocalSearchSourceResponse
}

struct LocalSearchReport: Equatable, Sendable {
    let results: [LocalSearchResult]
    let accessBySource: [LocalSearchSourceKind: LocalSearchAccess]
    var clearResult: LocalSearchResult? {
        guard results.count == 1 || (results.count > 1 && score(results[0]) - score(results[1]) >= 25) else { return nil }
        return results.first
    }

    private func score(_ result: LocalSearchResult) -> Int {
        result.relevance + (result.exactNameMatch ? 40 : 0)
    }
}

struct LocaliPhoneSearchEngine: Sendable {
    let sources: [any LocalSearchSource]

    func search(_ query: LocalSearchQuery) async -> LocalSearchReport {
        let selected = sources.filter { query.preferredSources.isEmpty || query.preferredSources.contains($0.kind) }
        let responses = await withTaskGroup(of: LocalSearchSourceResponse.self) { group in
            for source in selected { group.addTask { await source.search(query) } }
            var values: [LocalSearchSourceResponse] = []
            for await response in group { values.append(response) }
            return values
        }
        let access = Dictionary(uniqueKeysWithValues: responses.map { ($0.source, $0.access) })
        let ranked = responses.flatMap(\.results)
            .filter { result in query.dateRange.map { range in result.occurredAt.map(range.contains) ?? false } ?? true }
            .sorted { lhs, rhs in
                let left = rank(lhs, query: query), right = rank(rhs, query: query)
                if left != right { return left > right }
                if lhs.occurredAt != rhs.occurredAt { return (lhs.occurredAt ?? .distantPast) > (rhs.occurredAt ?? .distantPast) }
                if lhs.source != rhs.source { return lhs.source.rawValue < rhs.source.rawValue }
                return lhs.id < rhs.id
            }
        return LocalSearchReport(results: Array(ranked.prefix(query.limit)), accessBySource: access)
    }

    private func rank(_ result: LocalSearchResult, query: LocalSearchQuery) -> Int {
        let sourceBonus = query.preferredSources.contains(result.source) ? 20 : 0
        return result.relevance + sourceBonus + (result.exactNameMatch ? 40 : 0)
    }
}

actor PrivacySafeLocalSearchIndex {
    private var records: [String: LocalSearchResult] = [:]

    func upsert(_ changed: [LocalSearchResult]) {
        for value in changed { records["\(value.source.rawValue):\(value.id)"] = value }
    }

    func remove(source: LocalSearchSourceKind) {
        records = records.filter { $0.value.source != source }
    }

    func search(_ query: String, permittedSources: Set<LocalSearchSourceKind>) -> [LocalSearchResult] {
        let normalized = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return records.values.filter {
            permittedSources.contains($0.source) &&
            $0.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(normalized)
        }.sorted { $0.id < $1.id }
    }
}
