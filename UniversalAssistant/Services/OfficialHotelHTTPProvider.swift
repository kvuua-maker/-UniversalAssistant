import Foundation

protocol HotelHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, Int)
}

struct URLSessionHotelTransport: HotelHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw HotelHTTPError.invalidResponse }
        return (data, response.statusCode)
    }
}

enum HotelHTTPError: Error, Equatable {
    case missingCredential, invalidConfiguration, invalidResponse, unauthorized, rateLimited, providerFailure(Int)
}

struct OfficialHotelHTTPProvider: HotelProvider {
    let providerID: String
    private let searchURL: URL
    private let bearerToken: String
    private let transport: any HotelHTTPTransport

    init(providerID: String, searchURL: URL, bearerToken: String,
         transport: any HotelHTTPTransport = URLSessionHotelTransport()) throws {
        let token = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw HotelHTTPError.missingCredential }
        guard !providerID.isEmpty, searchURL.scheme?.lowercased() == "https", searchURL.host != nil else {
            throw HotelHTTPError.invalidConfiguration
        }
        self.providerID = providerID
        self.searchURL = searchURL
        self.bearerToken = token
        self.transport = transport
    }

    func search(_ input: HotelSearchRequest) async throws -> [HotelOffer] {
        let requestBody = try input.validated()
        var request = URLRequest(url: searchURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        let (data, status) = try await transport.data(for: request)
        if status == 401 || status == 403 { throw HotelHTTPError.unauthorized }
        if status == 429 { throw HotelHTTPError.rateLimited }
        guard (200..<300).contains(status), !data.isEmpty else { throw HotelHTTPError.providerFailure(status) }
        return try JSONDecoder().decode([HotelOffer].self, from: data).filter { $0.providerID == providerID }
    }
}
