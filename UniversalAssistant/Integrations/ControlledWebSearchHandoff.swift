import Foundation

enum WebSearchHandoffError: Error, Equatable, Sendable {
    case structuredCapabilityAvailable
    case emptyQuery
    case invalidDestination
}

struct ControlledWebSearchHandoff: Sendable {
    private let endpoint = URL(string: "https://www.google.com/search")!

    func destination(for command: StructuredCommand, structuredCapabilityAvailable: Bool) throws -> URL {
        guard command.intent == .webSearch, !structuredCapabilityAvailable else {
            throw WebSearchHandoffError.structuredCapabilityAvailable
        }
        let query = extractedQuery(from: command.originalText)
        guard !query.isEmpty else { throw WebSearchHandoffError.emptyQuery }
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [.init(name: "q", value: query)]
        guard let url = components?.url, url.scheme == "https", url.host == endpoint.host else {
            throw WebSearchHandoffError.invalidDestination
        }
        return url
    }

    private func extractedQuery(from text: String) -> String {
        let prefixes = ["пошукай в інтернеті", "поищи в интернете", "search the web", "im web suchen", "recherche sur le web"]
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = prefixes.compactMap({ trimmed.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) })
            .min(by: { $0.lowerBound < $1.lowerBound }) else { return "" }
        return trimmed[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
