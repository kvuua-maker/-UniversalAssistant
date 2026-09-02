import Foundation

enum PersonalSearchSourceID: Hashable, Sendable {
    case local(LocalSearchSourceKind)
    case connectedEmail(String)
    case connectedService(String)
}

enum PersonalSearchFreshness: Equatable, Sendable { case local, live(Date), cached(Date), unknown }

struct PersonalSearchResult: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let source: PersonalSearchSourceID
    let sourceObjectID: String
    let openReference: String
    let freshness: PersonalSearchFreshness
    let relevance: Int
    let exactMatch: Bool
}

struct PersonalSearchSourceResponse: Sendable {
    let source: PersonalSearchSourceID
    let results: [PersonalSearchResult]
    let isComplete: Bool
    let unavailableReason: String?
}

protocol PersonalSearchSource: Sendable {
    var id: PersonalSearchSourceID { get }
    func search(query: String, limit: Int) async -> PersonalSearchSourceResponse
}

enum PersonalSearchPresentation: Equatable, Sendable {
    case exactOpen(PersonalSearchResult)
    case shortlist([PersonalSearchResult])
    case noResult
}

struct UniversalPersonalSearchReport: Equatable, Sendable {
    let presentation: PersonalSearchPresentation
    let searchedSources: Set<PersonalSearchSourceID>
    let failedSources: [PersonalSearchSourceID: String]
    var isPartial: Bool { !failedSources.isEmpty }
}

struct PersonalSearchSourceRouter: Sendable {
    func sources(for query: String, available: Set<PersonalSearchSourceID>) -> Set<PersonalSearchSourceID> {
        let value = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        var desired = Set<PersonalSearchSourceID>()
        func local(_ kinds: Set<LocalSearchSourceKind>) { desired.formUnion(available.filter { if case let .local(kind) = $0 { kinds.contains(kind) } else { false } }) }
        if contains(value, ["фото", "photo", "bild"]) { local([.photos]) }
        if contains(value, ["догов", "document", "file", "файл"]) {
            local([.files, .notes]); desired.formUnion(remoteEmail(in: available))
        }
        if contains(value, ["лист", "email", "mail", "квиток", "ticket", "рахунок", "invoice"]) { desired.formUnion(remoteEmail(in: available)) }
        if contains(value, ["запис", "appointment", "зустріч", "стоматолог", "dentist"]) { local([.calendar, .reminders, .notes, .actionHistory]) }
        return desired.isEmpty ? available : desired
    }

    private func remoteEmail(in values: Set<PersonalSearchSourceID>) -> Set<PersonalSearchSourceID> {
        values.filter { if case .connectedEmail = $0 { true } else { false } }
    }
    private func contains(_ value: String, _ terms: [String]) -> Bool { terms.contains(where: value.contains) }
}

struct UniversalPersonalSearchEngine: Sendable {
    let sources: [any PersonalSearchSource]
    let router = PersonalSearchSourceRouter()

    func search(_ query: String, requestsImmediateOpen: Bool = false) async -> UniversalPersonalSearchReport {
        let selectedIDs = router.sources(for: query, available: Set(sources.map(\.id)))
        let selected = sources.filter { selectedIDs.contains($0.id) }
        let responses = await withTaskGroup(of: PersonalSearchSourceResponse.self) { group in
            for source in selected { group.addTask { await source.search(query: query, limit: 5) } }
            var output: [PersonalSearchSourceResponse] = []
            for await response in group { output.append(response) }
            return output
        }
        let failures = Dictionary(uniqueKeysWithValues: responses.compactMap { response in
            response.isComplete ? nil : (response.source, response.unavailableReason ?? "unavailable")
        })
        let ranked = responses.flatMap(\.results).sorted {
            let left = $0.relevance + ($0.exactMatch ? 40 : 0), right = $1.relevance + ($1.exactMatch ? 40 : 0)
            if left != right { return left > right }
            if $0.sourceObjectID != $1.sourceObjectID { return $0.sourceObjectID < $1.sourceObjectID }
            return $0.id < $1.id
        }
        let presentation: PersonalSearchPresentation
        if ranked.isEmpty { presentation = .noResult }
        else if requestsImmediateOpen && (ranked.count == 1 || score(ranked[0]) - score(ranked[1]) >= 25) { presentation = .exactOpen(ranked[0]) }
        else { presentation = .shortlist(Array(ranked.prefix(3))) }
        return .init(presentation: presentation, searchedSources: selectedIDs, failedSources: failures)
    }

    private func score(_ value: PersonalSearchResult) -> Int { value.relevance + (value.exactMatch ? 40 : 0) }
}
