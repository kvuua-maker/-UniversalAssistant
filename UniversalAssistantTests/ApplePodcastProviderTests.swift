import Foundation
import Testing
@testable import UniversalAssistant

private actor PodcastTransportSpy: PodcastHTTPTransport {
    let response: (Data, Int); var request: URLRequest?
    init(_ response: (Data, Int)) { self.response = response }
    func data(for request: URLRequest) -> (Data, Int) { self.request = request; return response }
}

@Suite("Apple podcast provider") struct ApplePodcastProviderTests {
    @Test func searchesPublicAPIWithBoundedRegionAndExactHandoff() async throws {
        let json = #"{"results":[{"trackId":42,"trackName":"Episode","collectionName":"Show","releaseDate":"2026-07-01T10:00:00Z","trackViewUrl":"https://podcasts.apple.com/ua/podcast/id42"}]}"#
        let transport = PodcastTransportSpy((Data(json.utf8), 200))
        let result = try await ApplePodcastSearchProvider(transport: transport).search("science", limit: 100, country: "ua")
        #expect(result.map(\.id) == ["42"])
        let url = try #require(await transport.request?.url)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(query?.first { $0.name == "limit" }?.value == "25")
        #expect(query?.first { $0.name == "country" }?.value == "UA")
    }

    @Test func invalidProviderRowsAndErrorsNeverBecomeResults() async throws {
        let invalid = PodcastTransportSpy((Data(#"{"results":[{"trackId":1,"trackName":"x","trackViewUrl":"javascript:bad"}]}"#.utf8), 200))
        #expect(try await ApplePodcastSearchProvider(transport: invalid).search("x", country: "UA").isEmpty)
        let failed = PodcastTransportSpy((Data(), 503))
        await #expect(throws: PodcastProviderError.http(503)) { try await ApplePodcastSearchProvider(transport: failed).search("x", country: "UA") }
    }
}
