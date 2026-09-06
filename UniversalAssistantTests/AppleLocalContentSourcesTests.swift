import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Authorized local content sources") struct AppleLocalContentSourcesTests {
    private struct PhotoLibraryStub: PhotoLibrarySearching {
        let access: LocalSearchAccess
        let assets: [PhotoAssetReference]
        func authorization() -> LocalSearchAccess { access }
        func requestAuthorization() async -> LocalSearchAccess { access }
        func search(_ criteria: PhotoSearchCriteria, limit: Int) async -> [PhotoAssetReference] { Array(assets.prefix(limit)) }
    }
    private struct ImageLoaderStub: PhotoAssetImageLoading {
        let dataByIdentifier: [String: Data]
        func imageData(localIdentifier: String) async throws -> Data {
            guard let data = dataByIdentifier[localIdentifier] else { throw CocoaError(.fileNoSuchFile) }
            return data
        }
    }
    private struct SemanticLabelerStub: PhotoSemanticLabeling {
        let labelsByPayload: [String: [PhotoSemanticLabel]]
        func labels(imageData: Data) async throws -> [PhotoSemanticLabel] {
            labelsByPayload[String(decoding: imageData, as: UTF8.self)] ?? []
        }
    }
    @Test func fileSearchUsesOnlyExplicitReferencesAndReturnsExactOpenURL() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let permitted = directory.appending(path: "Dental Plan.txt")
        let unrelated = directory.appending(path: "Secret.txt")
        try Data("controlled".utf8).write(to: permitted)
        try Data("not indexed".utf8).write(to: unrelated)
        let source = AuthorizedFileSearchSource(references: [.init(url: permitted, authorizedAt: .now)])
        let report = await source.search(.init(text: "Dental"))
        #expect(report.results.count == 1)
        #expect(report.results.first?.openReference == permitted.absoluteString)
        #expect(!report.results.contains { $0.openReference == unrelated.absoluteString })
    }

    @Test func replacingAuthorizationRemovesPreviouslyVisibleFile() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "ua-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: file)
        let source = AuthorizedFileSearchSource(references: [.init(url: file, authorizedAt: .now)])
        #expect((await source.search(.init(text: "ua-"))).results.count == 1)
        await source.replaceAuthorizedReferences([])
        #expect((await source.search(.init(text: "ua-"))).results.isEmpty)
    }

    @Test func photoCriteriaPreservesHardMetadataFilters() {
        let start = Date(timeIntervalSince1970: 1), end = Date(timeIntervalSince1970: 2)
        let criteria = PhotoSearchCriteria(dateRange: start..<end, coordinate: .init(latitude: 50.45, longitude: 30.52), radiusMeters: 500, albumName: "Trip")
        #expect(criteria.dateRange == start..<end)
        #expect(criteria.radiusMeters == 500)
        #expect(criteria.albumName == "Trip")
    }


    @Test func semanticPhotoSearchReturnsOnlyAccessibleMatchingAssetsInLibraryOrder() async {
        let first = PhotoAssetReference(localIdentifier: "first", creationDate: nil, coordinate: nil, album: nil)
        let second = PhotoAssetReference(localIdentifier: "second", creationDate: nil, coordinate: nil, album: nil)
        let engine = PhotoSemanticSearchEngine(
            library: PhotoLibraryStub(access: .limited, assets: [first, second]),
            loader: ImageLoaderStub(dataByIdentifier: ["first": Data("mountain".utf8), "second": Data("dog".utf8)]),
            labeler: SemanticLabelerStub(labelsByPayload: [
                "mountain": [.init(name: "mountain landscape", confidence: 0.91)],
                "dog": [.init(name: "domestic dog", confidence: 0.87)]
            ])
        )
        #expect(await engine.search("dog", limit: 5) == [second])
    }

    @Test func semanticPhotoSearchFailsClosedForDeniedAndUnreadableAssets() async {
        let asset = PhotoAssetReference(localIdentifier: "unreadable", creationDate: nil, coordinate: nil, album: nil)
        let denied = PhotoSemanticSearchEngine(library: PhotoLibraryStub(access: .denied, assets: [asset]), loader: ImageLoaderStub(dataByIdentifier: [:]), labeler: SemanticLabelerStub(labelsByPayload: [:]))
        let permitted = PhotoSemanticSearchEngine(library: PhotoLibraryStub(access: .permitted, assets: [asset]), loader: ImageLoaderStub(dataByIdentifier: [:]), labeler: SemanticLabelerStub(labelsByPayload: [:]))
        #expect((await denied.search("receipt")).isEmpty)
        #expect((await permitted.search("receipt")).isEmpty)
    }
}
