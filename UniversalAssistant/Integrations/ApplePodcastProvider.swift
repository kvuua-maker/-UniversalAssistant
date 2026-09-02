import Foundation

struct PodcastEpisodeResult: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let show: String?
    let publishedAt: Date?
    let exactURL: URL
}

protocol PodcastHTTPTransport: Sendable { func data(for request: URLRequest) async throws -> (Data, Int) }
struct URLSessionPodcastTransport: PodcastHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PodcastProviderError.invalidResponse }
        return (data, http.statusCode)
    }
}
enum PodcastProviderError: Error, Equatable { case invalidQuery, invalidResponse, http(Int) }

struct ApplePodcastSearchProvider: Sendable {
    let transport: any PodcastHTTPTransport
    init(transport: any PodcastHTTPTransport = URLSessionPodcastTransport()) { self.transport = transport }

    func search(_ query: String, limit: Int = 10, country: String) async throws -> [PodcastEpisodeResult] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, country.count == 2 else { throw PodcastProviderError.invalidQuery }
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [.init(name: "term", value: term), .init(name: "country", value: country.uppercased()),
            .init(name: "media", value: "podcast"), .init(name: "entity", value: "podcastEpisode"),
            .init(name: "limit", value: String(max(1, min(limit, 25))))]
        let (data, status) = try await transport.data(for: URLRequest(url: components.url!))
        guard (200..<300).contains(status) else { throw PodcastProviderError.http(status) }
        let wire: SearchWire
        do { wire = try JSONDecoder().decode(SearchWire.self, from: data) }
        catch { throw PodcastProviderError.invalidResponse }
        return wire.results.compactMap { item in
            guard let id = item.trackId, let title = item.trackName, let textURL = item.trackViewUrl,
                  let url = URL(string: textURL), url.scheme == "https", url.host != nil else { return nil }
            return .init(id: String(id), title: title, show: item.collectionName,
                         publishedAt: item.releaseDate.flatMap(ISO8601DateFormatter().date), exactURL: url)
        }
    }
}

private struct SearchWire: Decodable { let results: [Item] }
private struct Item: Decodable {
    let trackId: Int?; let trackName: String?; let collectionName: String?
    let releaseDate: String?; let trackViewUrl: String?
}
