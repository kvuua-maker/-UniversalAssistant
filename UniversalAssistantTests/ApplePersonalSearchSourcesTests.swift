import Foundation
import Testing
@testable import UniversalAssistant

private actor ContactSearchStub: PersonalContactSearching {
    let resolution: ContactResolution; init(_ resolution: ContactResolution) { self.resolution = resolution }
    func requestAccessIfNeeded() {}
    func resolve(name: String) -> ContactResolution { resolution }
}
private struct PhotoLibraryStub: PhotoLibrarySearching {
    let access: LocalSearchAccess; let values: [PhotoAssetReference]
    func authorization() -> LocalSearchAccess { access }
    func requestAuthorization() async -> LocalSearchAccess { access }
    func search(_ criteria: PhotoSearchCriteria, limit: Int) async -> [PhotoAssetReference] { Array(values.prefix(limit)) }
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
        #expect(response.isComplete); #expect(response.results.first?.sourceObjectID == "p1"); #expect(response.results.first?.openReference == "ph://p1")
    }
    @Test func filesAdapterRejectsUnauthorizedAndPreservesOpenReference() async {
        let item = LocalSearchResult(id: "f1", source: .files, title: "Contract.pdf", subtitle: nil, occurredAt: nil, exactNameMatch: true, relevance: 70, openReference: "file:///authorized/Contract.pdf")
        let allowed = await LocalPersonalSearchSourceAdapter(source: LocalSourceStub(kind: .files, access: .limited, values: [item])).search(query: "Contract", limit: 3)
        #expect(allowed.results.first?.sourceObjectID == "f1"); #expect(allowed.results.first?.openReference == item.openReference)
        let denied = await LocalPersonalSearchSourceAdapter(source: LocalSourceStub(kind: .files, access: .denied, values: [item])).search(query: "Contract", limit: 3)
        #expect(!denied.isComplete); #expect(denied.results.isEmpty)
    }
}
