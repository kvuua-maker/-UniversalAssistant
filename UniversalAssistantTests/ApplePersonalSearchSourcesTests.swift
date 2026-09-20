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
private struct LabelerStub: PhotoSemanticLabeling { func labels(imageData: Data) async throws -> [PhotoSemanticLabel] { [.init(name: "receipt", confidence: 1)] } }
private struct LocalSourceStub: LocalSearchSource {
    let kind: LocalSearchSourceKind; let access: LocalSearchAccess; let values: [LocalSearchResult]
    func search(_ query: LocalSearchQuery) async -> LocalSearchSourceResponse { .init(source: kind, access: access, results: Array(values.prefix(query.limit))) }
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
