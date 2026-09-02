import Foundation

protocol TicketHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, Int)
}

struct URLSessionTicketTransport: TicketHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw TicketHTTPError.invalidResponse }
        return (data, response.statusCode)
    }
}

enum TicketHTTPError: Error, Equatable {
    case missingCredential, invalidConfiguration, invalidResponse, unauthorized, rateLimited, providerFailure(Int)
}

struct OfficialTicketHTTPProvider: TicketProvider {
    let providerID: String
    private let searchURL: URL
    private let bearerToken: String
    private let transport: any TicketHTTPTransport

    init(providerID: String, searchURL: URL, bearerToken: String,
         transport: any TicketHTTPTransport = URLSessionTicketTransport()) throws {
        let token = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw TicketHTTPError.missingCredential }
        guard !providerID.isEmpty, searchURL.scheme?.lowercased() == "https", searchURL.host != nil else {
            throw TicketHTTPError.invalidConfiguration
        }
        self.providerID = providerID
        self.searchURL = searchURL
        self.bearerToken = token
        self.transport = transport
    }

    func search(_ requestBody: TicketSearchRequest) async throws -> [TicketOffer] {
        var request = URLRequest(url: searchURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        let (data, status) = try await transport.data(for: request)
        if status == 401 || status == 403 { throw TicketHTTPError.unauthorized }
        if status == 429 { throw TicketHTTPError.rateLimited }
        guard (200..<300).contains(status), !data.isEmpty else { throw TicketHTTPError.providerFailure(status) }
        let offers = try JSONDecoder().decode([TicketOffer].self, from: data)
        return offers.filter { $0.providerID == providerID }
    }
}
