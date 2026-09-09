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
    private struct DelayedSemanticLabelerStub: PhotoSemanticLabeling {
        let delay: Duration
        func labels(imageData: Data) async throws -> [PhotoSemanticLabel] {
            try await Task.sleep(for: delay)
            return [.init(name: "automobile", confidence: 0.91)]
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
    @Test func semanticPhotoSearchRejectsWeakClassificationInsteadOfReturningAnAsset() async {
        let asset = PhotoAssetReference(localIdentifier: "weak", creationDate: nil, coordinate: nil, album: nil)
        let engine = PhotoSemanticSearchEngine(
            library: PhotoLibraryStub(access: .permitted, assets: [asset]),
            loader: ImageLoaderStub(dataByIdentifier: ["weak": Data("weak".utf8)]),
            labeler: SemanticLabelerStub(labelsByPayload: ["weak": [.init(name: "invoice document", confidence: 0.64)]])
        )
        #expect((await engine.matches("document", limit: 3)).isEmpty)
    }

    @Test func semanticPhotoSearchCarriesConfidenceAndRanksStrongestEvidenceFirst() async {
        let older = PhotoAssetReference(localIdentifier: "older", creationDate: nil, coordinate: nil, album: nil)
        let newer = PhotoAssetReference(localIdentifier: "newer", creationDate: nil, coordinate: nil, album: nil)
        let engine = PhotoSemanticSearchEngine(
            library: PhotoLibraryStub(access: .limited, assets: [newer, older]),
            loader: ImageLoaderStub(dataByIdentifier: ["newer": Data("newer".utf8), "older": Data("older".utf8)]),
            labeler: SemanticLabelerStub(labelsByPayload: [
                "newer": [.init(name: "domestic animal", confidence: 0.73)],
                "older": [.init(name: "domestic animal", confidence: 0.94)]
            ])
        )
        let matches = await engine.matches("animal", limit: 3)
        #expect(matches.map(\.asset.localIdentifier) == ["older", "newer"])
        #expect(matches.map(\.confidence) == [0.94, 0.73])
        #expect(matches.first?.matchedLabels == ["domestic animal"])
    }

    @Test func filesQueryDeadlineTerminatesBeforeLateSynchronousCompletion() async {
        // Keep the simulated provider slower than worst-case parallel-suite
        // scheduling so this proves the independent deadline rather than timing luck.
        let query = SystemAuthorizedFileQuery { _, _ in Thread.sleep(forTimeInterval: 8); return [] }
        let source = AuthorizedFileSearchSource(query: query, timeout: .milliseconds(20))
        let clock = ContinuousClock(); let start = clock.now
        let response = await source.search(.init(text: "PDF"))
        #expect(response.access == .unavailable)
        #expect(response.results.isEmpty)
        #expect(start.duration(to: clock.now) < .seconds(6))
        try? await Task.sleep(for: .milliseconds(20))
        #expect(response.results.isEmpty)
    }

    @Test func filesQueryCancellationTerminatesWithoutPublishingLateResults() async {
        let late = LocalSearchResult(id: "late", source: .files, title: "late.pdf", subtitle: nil, occurredAt: nil, exactNameMatch: true, relevance: 100, openReference: "file:///late.pdf")
        let query = SystemAuthorizedFileQuery { _, _ in Thread.sleep(forTimeInterval: 1.5); return [late] }
        let source = AuthorizedFileSearchSource(query: query, timeout: .seconds(3))
        let task = Task { await source.search(.init(text: "late")) }
        try? await Task.sleep(for: .milliseconds(10)); task.cancel()
        let response = await task.value
        #expect(response.access == .unavailable)
        #expect(response.results.isEmpty)
    }
}
