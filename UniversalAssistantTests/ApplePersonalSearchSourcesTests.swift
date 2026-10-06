import Foundation
import Testing
@testable import UniversalAssistant

private actor ContactSearchStub: PersonalContactSearching, ContactResolving {
    let resolution: ContactResolution; init(_ resolution: ContactResolution) { self.resolution = resolution }
    func requestAccessIfNeeded() {}
    func resolve(name: String) -> ContactResolution { resolution }
    func resolve(exactIdentifier identifier: String) -> ContactResolution { resolution }
}
private struct PhotoLibraryStub: PhotoLibrarySearching {
    let access: LocalSearchAccess; let values: [PhotoAssetReference]
    func authorization() -> LocalSearchAccess { access }
    func requestAuthorization() async -> LocalSearchAccess { access }
    func search(_ criteria: PhotoSearchCriteria, limit: Int) async -> [PhotoAssetReference] { Array(values.prefix(limit)) }
}
private final class TransitioningPhotoLibraryStub: PhotoLibrarySearching, @unchecked Sendable {
    private let lock = NSLock()
    private var current: LocalSearchAccess
    private let granted: LocalSearchAccess
    private let values: [PhotoAssetReference]
    private(set) var requestCount = 0
    init(initial: LocalSearchAccess, granted: LocalSearchAccess, values: [PhotoAssetReference]) { self.current = initial; self.granted = granted; self.values = values }
    func authorization() -> LocalSearchAccess { lock.withLock { current } }
    func requestAuthorization() async -> LocalSearchAccess { lock.withLock { requestCount += 1; current = granted; return current } }
    func search(_ criteria: PhotoSearchCriteria, limit: Int) async -> [PhotoAssetReference] { Array(values.prefix(limit)) }
}
private struct DelayedPhotoLibraryStub: PhotoLibrarySearching {
    let delay: Duration
    let values: [PhotoAssetReference]
    func authorization() -> LocalSearchAccess { .permitted }
    func requestAuthorization() async -> LocalSearchAccess { .permitted }
    func search(_ criteria: PhotoSearchCriteria, limit: Int) async -> [PhotoAssetReference] {
        try? await Task.sleep(for: delay)
        return Array(values.prefix(limit))
    }
}
private struct ImageLoaderStub: PhotoAssetImageLoading { func imageData(localIdentifier: String) async throws -> Data { Data() } }
private struct LabelerStub: PhotoSemanticLabeling {
    func labels(imageData: Data) async throws -> [PhotoSemanticLabel] { [.init(name: "receipt", confidence: 1)] }
    func documentLabels(imageData: Data) async throws -> [PhotoSemanticLabel] { [.init(name: "document", confidence: 1)] }
}
private struct LocalSourceStub: LocalSearchSource {
    let kind: LocalSearchSourceKind; let access: LocalSearchAccess; let values: [LocalSearchResult]
    func search(_ query: LocalSearchQuery) async -> LocalSearchSourceResponse { .init(source: kind, access: access, results: Array(values.prefix(query.limit))) }
}

private final class FilteredPhotoFixtureLibrary: PhotoLibrarySearching, @unchecked Sendable {
    let access: LocalSearchAccess
    let assets: [PhotoAssetReference]
    let visibleIDs: Set<String>
    private let lock = NSLock()
    private var criteriaHistory: [PhotoSearchCriteria] = []
    init(access: LocalSearchAccess, assets: [PhotoAssetReference], visibleIDs: Set<String>) {
        self.access = access; self.assets = assets; self.visibleIDs = visibleIDs
    }
    func authorization() -> LocalSearchAccess { access }
    func requestAuthorization() async -> LocalSearchAccess { access }
    func search(_ criteria: PhotoSearchCriteria, limit: Int) async -> [PhotoAssetReference] {
        lock.withLock { criteriaHistory.append(criteria) }
        guard [.permitted, .limited].contains(access) else { return [] }
        return Array(assets.filter { asset in
            guard access == .permitted || visibleIDs.contains(asset.localIdentifier) else { return false }
            guard let range = criteria.dateRange else { return true }
            return asset.creationDate.map { range.contains($0) } ?? false
        }.prefix(limit))
    }
    func queries() -> [PhotoSearchCriteria] { lock.withLock { criteriaHistory } }
}
private struct DocumentFixtureLoader: PhotoAssetImageLoading {
    func imageData(localIdentifier: String) async throws -> Data { Data(localIdentifier.utf8) }
}
private struct PartiallyUnavailableDocumentFixtureLoader: PhotoAssetImageLoading {
    func imageData(localIdentifier: String) async throws -> Data {
        if localIdentifier.contains("unreadable") { throw CocoaError(.fileReadNoSuchFile) }
        return Data(localIdentifier.utf8)
    }
}
private struct DocumentFixtureLabeler: PhotoSemanticLabeling {
    func labels(imageData: Data) async throws -> [PhotoSemanticLabel] { [] }
    func documentLabels(imageData: Data) async throws -> [PhotoSemanticLabel] {
        String(decoding: imageData, as: UTF8.self).contains("document") ? [.init(name: "document", confidence: 0.94)] : []
    }
}

private final class RevokingPhotoFixtureLibrary: PhotoLibrarySearching, @unchecked Sendable {
    private let lock = NSLock()
    private var access: LocalSearchAccess
    private let afterSearch: LocalSearchAccess
    private var hasSearched = false
    private let asset: PhotoAssetReference
    init(initial: LocalSearchAccess, afterSearch: LocalSearchAccess, asset: PhotoAssetReference) {
        access = initial; self.afterSearch = afterSearch; self.asset = asset
    }
    func authorization() -> LocalSearchAccess { lock.withLock { access } }
    func requestAuthorization() async -> LocalSearchAccess { authorization() }
    func search(_ criteria: PhotoSearchCriteria, limit: Int) async -> [PhotoAssetReference] {
        lock.withLock { access = afterSearch; hasSearched = true }
        return [asset] // Simulates an in-flight snapshot from before revocation.
    }
    func currentlyAccessible(_ assets: [PhotoAssetReference]) -> [PhotoAssetReference] {
        lock.withLock { hasSearched ? [] : assets }
    }
}

@Suite("Apple personal search adapters") struct ApplePersonalSearchSourcesTests {
    @Test func contactsPreserveAuthoritativeIdentifiersAndAmbiguity() async {
        let values = [ContactCandidate(identifier: "c1", displayName: "Mama", phoneNumbers: []), .init(identifier: "c2", displayName: "Mama Work", phoneNumbers: [])]
        let response = await ContactsPersonalSearchSource(contacts: ContactSearchStub(.ambiguous(values))).search(query: "Mama", limit: 3)
        #expect(response.isComplete); #expect(response.results.map(\.sourceObjectID) == ["c1", "c2"]); #expect(response.results.first?.openReference == "contact:c1")
    }
    @Test func photosRespectLimitedScopeAndPreserveAssetIdentifier() async {
        let asset = PhotoAssetReference(localIdentifier: "p1", creationDate: .init(timeIntervalSince1970: 1), coordinate: nil, album: nil)
        let source = PhotosPersonalSearchSource(library: PhotoLibraryStub(access: .limited, values: [asset]), loader: ImageLoaderStub(), labeler: LabelerStub())
        let response = await source.search(query: "receipt", limit: 3)
        #expect(response.isComplete); #expect(response.results.first?.sourceObjectID == "p1"); #expect(response.results.first?.openReference == "photo-asset:p1"); #expect(response.results.first?.relevance == 100)
    }
    @Test func filesAdapterRejectsUnauthorizedAndPreservesOpenReference() async {
        let item = LocalSearchResult(id: "f1", source: .files, title: "Contract.pdf", subtitle: nil, occurredAt: nil, exactNameMatch: true, relevance: 70, openReference: "file:///authorized/Contract.pdf")
        let allowed = await LocalPersonalSearchSourceAdapter(source: LocalSourceStub(kind: .files, access: .limited, values: [item])).search(query: "Contract", limit: 3)
        #expect(allowed.results.first?.sourceObjectID == "f1"); #expect(allowed.results.first?.openReference == item.openReference)
        let denied = await LocalPersonalSearchSourceAdapter(source: LocalSourceStub(kind: .files, access: .denied, values: [item])).search(query: "Contract", limit: 3)
        #expect(!denied.isComplete); #expect(denied.results.isEmpty)
    }
}

private struct ProductionPersonalSourceStub: PersonalSearchSource {
    let id: PersonalSearchSourceID = .local(.contacts)
    func search(query: String, limit: Int) async -> PersonalSearchSourceResponse {
        let value = PersonalSearchResult(id: "contacts:c1", title: "Mama", subtitle: nil, source: id, sourceObjectID: "c1", openReference: "contact:c1", freshness: .local, relevance: 100, exactMatch: true)
        return .init(source: id, results: [value], isComplete: true, unavailableReason: nil)
    }
}

extension ApplePersonalSearchSourcesTests {
    @Test @MainActor func revokedAccessCannotPublishLatePhotoResults() async throws {
        let asset = PhotoAssetReference(localIdentifier: "revoked-document-" + UUID().uuidString, creationDate: .now,
                                        coordinate: nil, album: nil)
        let library = RevokingPhotoFixtureLibrary(initial: .permitted, afterSearch: .denied, asset: asset)
        let response = await PhotosPersonalSearchSource(library: library).search(query: "", limit: 5)
        #expect(response.results.isEmpty)
        #expect(response.unavailableReason == "photos_access_unavailable")
        for phrase in ["Відкрий фото за минулий рік", "Відкрий найновіше фото", "Відкрий фото документів"] {
            let executor = ProductionCanonicalCapabilityExecutor(
                photos: RevokingPhotoFixtureLibrary(initial: .permitted, afterSearch: .denied, asset: asset),
                photoSemanticLoader: DocumentFixtureLoader(), photoSemanticLabeler: DocumentFixtureLabeler(), personalSearchSources: [])
            do { _ = try await executor.execute(LocalCommandEngine().parse(phrase)); Issue.record("Revoked photo reference escaped") }
            catch let error as CanonicalCapabilityExecutionError { #expect(error == .unavailable("photos_access_unavailable")) }
        }
    }

    @Test @MainActor func changedLimitedSelectionCannotPublishAnEarlierAssetSnapshot() async throws {
        let asset = PhotoAssetReference(localIdentifier: "removed-document-" + UUID().uuidString, creationDate: .now,
                                        coordinate: nil, album: nil)
        for initial in [LocalSearchAccess.permitted, .limited] {
            for query in ["", "document"] {
                let library = RevokingPhotoFixtureLibrary(initial: initial, afterSearch: .limited, asset: asset)
                let response = await PhotosPersonalSearchSource(library: library, loader: DocumentFixtureLoader(), labeler: DocumentFixtureLabeler())
                    .search(query: query, limit: 5)
                #expect(response.results.isEmpty)
                #expect(response.unavailableReason == "photos_access_changed")
            }
            let executor = ProductionCanonicalCapabilityExecutor(
                photos: RevokingPhotoFixtureLibrary(initial: initial, afterSearch: .limited, asset: asset), personalSearchSources: [])
            let outcome = try await executor.execute(LocalCommandEngine().parse("Відкрий фото за минулий рік"))
            guard case let .result(result) = outcome else { Issue.record("Expected truthful limited no-match result"); continue }
            #expect(result.actions.isEmpty)
            #expect(result.facts.isEmpty)
        }
    }

    @Test @MainActor func partialPositivePhotoSearchIsLabeledIncompleteInProductionResult() async throws {
        let fixtureID = UUID().uuidString
        let values = ["document-", "unreadable-"].map {
            PhotoAssetReference(localIdentifier: $0 + fixtureID, creationDate: .now, coordinate: nil, album: nil)
        }
        let executor = ProductionCanonicalCapabilityExecutor(photos: PhotoLibraryStub(access: .limited, values: values),
                                                              photoSemanticLoader: PartiallyUnavailableDocumentFixtureLoader(),
                                                              photoSemanticLabeler: DocumentFixtureLabeler(), personalSearchSources: [])
        let outcome = try await executor.execute(LocalCommandEngine().parse("Знайди фото документів"))
        guard case let .result(result) = outcome else { Issue.record("Expected partial photo results"); return }
        #expect(result.primaryAnswer.contains("не повністю"))
        #expect(result.actions.map(\.id) == ["photos:" + values[0].localIdentifier])
    }

    @Test @MainActor func previousCalendarYearUsesMetadataBeforeFetchingAccessibleAssets() async throws {
        let calendar = Calendar.autoupdatingCurrent
        let thisYear = try #require(calendar.dateInterval(of: .year, for: .now)?.start)
        let previousYear = try #require(calendar.date(byAdding: .year, value: -1, to: thisYear))
        let fixtureID = UUID().uuidString
        let values = [
            PhotoAssetReference(localIdentifier: "current-\(fixtureID)", creationDate: thisYear, coordinate: nil, album: nil),
            PhotoAssetReference(localIdentifier: "private-\(fixtureID)", creationDate: thisYear.addingTimeInterval(-1), coordinate: nil, album: nil),
            PhotoAssetReference(localIdentifier: "previous-\(fixtureID)", creationDate: previousYear, coordinate: nil, album: nil),
            PhotoAssetReference(localIdentifier: "older-\(fixtureID)", creationDate: previousYear.addingTimeInterval(-1), coordinate: nil, album: nil)
        ]
        let library = FilteredPhotoFixtureLibrary(access: .limited, assets: values, visibleIDs: [values[0].localIdentifier, values[2].localIdentifier, values[3].localIdentifier])
        let executor = ProductionCanonicalCapabilityExecutor(photos: library, personalSearchSources: [])
        let command = LocalCommandEngine().parse("Відкрий фото за минулий рік")
        #expect(command.intent == .photoSearch)
        #expect(command.entities["photo_query_kind"] == "metadata")
        #expect(try await executor.execute(command) == .presentation(.photoAsset(values[2].localIdentifier)))
        #expect(library.queries().count == 1)
        #expect(library.queries().first?.dateRange == previousYear..<thisYear)
    }

    @Test @MainActor func documentPhotoRouteCombinesOCRDateAndLimitedAuthorization() async throws {
        let thisYear = try #require(Calendar.autoupdatingCurrent.dateInterval(of: .year, for: .now)?.start)
        let fixtureID = UUID().uuidString
        let values = [
            PhotoAssetReference(localIdentifier: "new-document-\(fixtureID)", creationDate: thisYear, coordinate: nil, album: nil),
            PhotoAssetReference(localIdentifier: "private-document-\(fixtureID)", creationDate: thisYear.addingTimeInterval(-10), coordinate: nil, album: nil),
            PhotoAssetReference(localIdentifier: "blank-\(fixtureID)", creationDate: thisYear.addingTimeInterval(-20), coordinate: nil, album: nil),
            PhotoAssetReference(localIdentifier: "old-document-\(fixtureID)", creationDate: thisYear.addingTimeInterval(-30), coordinate: nil, album: nil)
        ]
        let visibleIDs: Set<String> = [values[0].localIdentifier, values[2].localIdentifier, values[3].localIdentifier]
        for access in [LocalSearchAccess.limited, .permitted, .denied] {
            let library = FilteredPhotoFixtureLibrary(access: access, assets: values, visibleIDs: visibleIDs)
            let executor = ProductionCanonicalCapabilityExecutor(photos: library, photoSemanticLoader: DocumentFixtureLoader(),
                                                                  photoSemanticLabeler: DocumentFixtureLabeler(), personalSearchSources: [])
            let command = LocalCommandEngine().parse("Відкрий фото документів за минулий рік")
            #expect(command.intent == .photoSearch)
            #expect(command.entities["photo_query_kind"] == "semantic")
            if access == .denied {
                do { _ = try await executor.execute(command); Issue.record("Expected denied Photos boundary") }
                catch let error as CanonicalCapabilityExecutionError { #expect(error == .unavailable("photos_access_unavailable")) }
                #expect(library.queries().isEmpty)
            } else {
                let expected = access == .limited ? values[3] : values[1]
                #expect(try await executor.execute(command) == .presentation(.photoAsset(expected.localIdentifier)))
                #expect(library.queries().count == 1)
                #expect(library.queries().first?.dateRange?.upperBound == thisYear)
            }
        }
    }

    @Test @MainActor func documentPhotoPhraseUsesOCRProductionRouteWithoutDateConstraint() async throws {
        let fixtureID = UUID().uuidString
        let blank = PhotoAssetReference(localIdentifier: "blank-\(fixtureID)", creationDate: .now, coordinate: nil, album: nil)
        let document = PhotoAssetReference(localIdentifier: "document-\(fixtureID)", creationDate: .distantPast, coordinate: nil, album: nil)
        let library = FilteredPhotoFixtureLibrary(access: .limited, assets: [blank, document], visibleIDs: [blank.localIdentifier, document.localIdentifier])
        let executor = ProductionCanonicalCapabilityExecutor(photos: library, photoSemanticLoader: DocumentFixtureLoader(),
                                                              photoSemanticLabeler: DocumentFixtureLabeler(), personalSearchSources: [])
        #expect(try await executor.execute(LocalCommandEngine().parse("Відкрий фото документів")) == .presentation(.photoAsset(document.localIdentifier)))
        #expect(library.queries().count == 1)
        #expect(library.queries().first?.dateRange == nil)
    }

    @Test @MainActor func productionRequestUsesPersonalSearchAndReturnsTypedResultAction() async throws {
        let contact = ContactCandidate(identifier: "c1", displayName: "Mama", phoneNumbers: ["+380501234567"])
        let executor = ProductionCanonicalCapabilityExecutor(contacts: ContactSearchStub(.resolved(contact)), personalSearchSources: [])
        let command = StructuredCommand(originalText: "Знайди контакт мама", normalizedText: "знайди контакт мама", language: .uk, intent: .contactLookup, entities: ["contact":"Mama"])
        #expect(try await executor.execute(command) == .presentation(.contactCard(identifier: "c1")))
    }
    @Test @MainActor func latestPhotoUsesOneNewestAssetAndInAppPresentationAction() async throws {
        let older = PhotoAssetReference(localIdentifier: "old", creationDate: .init(timeIntervalSince1970: 1), coordinate: nil, album: nil)
        let newest = PhotoAssetReference(localIdentifier: "new", creationDate: .init(timeIntervalSince1970: 2), coordinate: nil, album: nil)
        let executor = ProductionCanonicalCapabilityExecutor(photos: PhotoLibraryStub(access: .limited, values: [newest, older]), personalSearchSources: [])
        let command = LocalCommandEngine().parse("Відкрий найновіше фото")
        #expect(try await executor.execute(command) == .presentation(.photoAsset("new")))
    }
    @Test @MainActor func photoPermissionGrantContinuesPendingLatestRequest() async throws {
        let asset = PhotoAssetReference(localIdentifier: "granted", creationDate: .now, coordinate: nil, album: nil)
        let library = TransitioningPhotoLibraryStub(initial: .permissionRequired, granted: .permitted, values: [asset])
        let executor = ProductionCanonicalCapabilityExecutor(photos: library, personalSearchSources: [])
        let outcome = try await executor.execute(LocalCommandEngine().parse("Відкрий останнє фото"))
        #expect(library.requestCount == 1)
        #expect(outcome == .presentation(.photoAsset("granted")))
    }

    @Test @MainActor func photoMetadataQueryDeadlineTerminatesBeforeLateCompletion() async {
        let late = PhotoAssetReference(localIdentifier: "late", creationDate: .now, coordinate: nil, album: nil)
        let executor = ProductionCanonicalCapabilityExecutor(
            photos: DelayedPhotoLibraryStub(delay: .seconds(1), values: [late]),
            photoSearchTimeout: .milliseconds(20),
            personalSearchSources: []
        )
        let command = LanguageUnderstandingBlock().parse("Покажи недавній знімок")
        #expect(command.entities["photo_query_kind"] == "recent")
        do {
            _ = try await executor.execute(command)
            Issue.record("Expected bounded PhotoKit timeout")
        } catch let error as CanonicalCapabilityExecutionError {
            #expect(error == .unavailable("photos_search_timeout"))
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test @MainActor func latestPhotoFailsTruthfullyForDeniedAndEmptyLibrary() async {
        for library in [
            PhotoLibraryStub(access: .denied, values: []),
            PhotoLibraryStub(access: .permitted, values: [])
        ] {
            let executor = ProductionCanonicalCapabilityExecutor(photos: library, personalSearchSources: [])
            do { _ = try await executor.execute(LocalCommandEngine().parse("Відкрий найсвіжіше фото")); Issue.record("Expected unavailable photo result") }
            catch let error as CanonicalCapabilityExecutionError {
                #expect(error == .unavailable(library.access == .denied ? "photos_access_unavailable" : "photos_empty"))
            } catch { Issue.record("Unexpected error: \(error)") }
        }
    }
}
