import Foundation

protocol PersonalContactSearching: Sendable {
    func requestAccessIfNeeded() async throws
    func resolve(name: String) async throws -> ContactResolution
}
extension LocalContactResolver: PersonalContactSearching {}

struct ContactsPersonalSearchSource: PersonalSearchSource {
    let id: PersonalSearchSourceID = .local(.contacts)
    let contacts: any PersonalContactSearching
    init(contacts: any PersonalContactSearching = LocalContactResolver()) { self.contacts = contacts }
    func search(query: String, limit: Int) async -> PersonalSearchSourceResponse {
        do {
            try await contacts.requestAccessIfNeeded()
            let candidates: [ContactCandidate] = switch try await contacts.resolve(name: query) {
            case let .resolved(value): [value]
            case let .ambiguous(values): values
            case .notFound: []
            }
            let values = candidates.prefix(max(1, min(limit, 5))).map { value in
                PersonalSearchResult(id: "contacts:\(value.identifier)", title: value.displayName, subtitle: nil, source: id, sourceObjectID: value.identifier, openReference: "contact:\(value.identifier)", freshness: .local, relevance: 90, exactMatch: value.displayName.localizedCaseInsensitiveCompare(query) == .orderedSame)
            }
            return .init(source: id, results: values, isComplete: true, unavailableReason: nil)
        } catch {
            return .init(source: id, results: [], isComplete: false, unavailableReason: "contacts_access_unavailable")
        }
    }
}

struct PhotosPersonalSearchSource: PersonalSearchSource {
    let id: PersonalSearchSourceID = .local(.photos)
    let library: any PhotoLibrarySearching
    let loader: any PhotoAssetImageLoading
    let labeler: any PhotoSemanticLabeling
    init(library: any PhotoLibrarySearching = PhotoKitLibrarySearch(), loader: any PhotoAssetImageLoading = PhotoKitAssetImageLoader(), labeler: any PhotoSemanticLabeling = VisionPhotoSemanticLabeler()) { self.library = library; self.loader = loader; self.labeler = labeler }
    func search(query: String, limit: Int) async -> PersonalSearchSourceResponse {
        await search(query: query, criteria: .init(), limit: limit)
    }
    func search(query: String, criteria: PhotoSearchCriteria, limit: Int) async -> PersonalSearchSourceResponse {
        let access = library.authorization() == .permissionRequired ? await library.requestAuthorization() : library.authorization()
        guard access == .permitted || access == .limited else { return .init(source: id, results: [], isComplete: false, unavailableReason: "photos_access_unavailable") }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let ranked: [(PhotoAssetReference, Int)]
        var isComplete = true
        var unavailableReason: String?
        if trimmed.isEmpty {
            ranked = await library.search(criteria, limit: limit).enumerated().map { ($0.element, 80 - $0.offset) }
        } else {
            let report = await PhotoSemanticSearchEngine(library: library, loader: loader, labeler: labeler)
                .report(query, criteria: criteria, limit: limit)
            ranked = report.matches.map { ($0.asset, Int(($0.confidence * 100).rounded())) }
            isComplete = report.isComplete
            unavailableReason = report.timedOut ? "photos_search_timeout" : (report.isComplete ? nil : "photos_search_partial")
        }
        guard [.permitted, .limited].contains(library.authorization()) else {
            return .init(source: id, results: [], isComplete: false, unavailableReason: "photos_access_unavailable")
        }
        let visible = Set(library.currentlyAccessible(ranked.map { $0.0 }).map(\.localIdentifier))
        let accessible = ranked.filter { visible.contains($0.0.localIdentifier) }
        if accessible.count != ranked.count {
            isComplete = false
            unavailableReason = "photos_access_changed"
        }
        let values = accessible.enumerated().map { index, rankedAsset in
            let (asset, relevance) = rankedAsset
            return PersonalSearchResult(id: "photos:\(asset.localIdentifier)", title: "Фото \(index + 1)", subtitle: asset.creationDate?.formatted(), source: id, sourceObjectID: asset.localIdentifier, openReference: "photo-asset:" + asset.localIdentifier, freshness: .local, relevance: relevance, exactMatch: false)
        }
        return .init(source: id, results: values, isComplete: isComplete, unavailableReason: unavailableReason)
    }
}

struct LocalPersonalSearchSourceAdapter: PersonalSearchSource {
    let source: any LocalSearchSource
    var id: PersonalSearchSourceID { .local(source.kind) }
    func search(query: String, limit: Int) async -> PersonalSearchSourceResponse {
        let response = await source.search(.init(text: query, preferredSources: [source.kind], limit: limit))
        let allowed = response.access == .permitted || response.access == .limited
        let results = allowed ? response.results.map { value in PersonalSearchResult(id: "\(value.source.rawValue):\(value.id)", title: value.title, subtitle: value.subtitle, source: id, sourceObjectID: value.id, openReference: value.openReference, freshness: .local, relevance: value.relevance, exactMatch: value.exactNameMatch) } : []
        return .init(source: id, results: results, isComplete: allowed, unavailableReason: allowed ? nil : "\(source.kind.rawValue)_access_unavailable")
    }
}
