import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Authorized local content sources") struct AppleLocalContentSourcesTests {
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
}
