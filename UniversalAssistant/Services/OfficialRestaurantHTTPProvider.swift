import Foundation

protocol RestaurantHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, Int)
}

struct URLSessionRestaurantTransport: RestaurantHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw RestaurantHTTPError.invalidResponse }
        return (data, response.statusCode)
    }
}

enum RestaurantHTTPError: Error, Equatable {
    case missingCredential, invalidConfiguration, invalidResponse, unauthorized, rateLimited, providerFailure(Int)
}

struct RestaurantProviderConfiguration: Sendable {
    let providerID: String
    let availabilityURL: URL
    let bookingURL: URL
}

struct OfficialRestaurantHTTPProvider: ReservationProvider {
    let providerID: String
    private let availabilityURL: URL
    private let bookingURL: URL
    private let bearerToken: String
    private let transport: any RestaurantHTTPTransport

    init(configuration: RestaurantProviderConfiguration, bearerToken: String,
         transport: any RestaurantHTTPTransport = URLSessionRestaurantTransport()) throws {
        let token = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw RestaurantHTTPError.missingCredential }
        guard configuration.availabilityURL.scheme == "https", configuration.bookingURL.scheme == "https",
              !configuration.providerID.isEmpty else { throw RestaurantHTTPError.invalidConfiguration }
        providerID = configuration.providerID
        availabilityURL = configuration.availabilityURL
        bookingURL = configuration.bookingURL
        self.bearerToken = token
        self.transport = transport
    }

    func availability(restaurantID: String, partySize: Int, interval: DateInterval) async throws -> [RestaurantReservationSlot] {
        struct Body: Encodable { let restaurantID: String; let partySize: Int; let startsAt: Date; let endsAt: Date }
        var request = base(availabilityURL)
        request.httpBody = try JSONEncoder().encode(Body(restaurantID: restaurantID, partySize: partySize,
                                                         startsAt: interval.start, endsAt: interval.end))
        return try JSONDecoder().decode([RestaurantReservationSlot].self, from: await execute(request))
    }

    func book(slotID: String) async throws -> RestaurantReservation {
        struct Body: Encodable { let slotID: String }
        var request = base(bookingURL)
        request.httpBody = try JSONEncoder().encode(Body(slotID: slotID))
        return try JSONDecoder().decode(RestaurantReservation.self, from: await execute(request))
    }

    private func base(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func execute(_ request: URLRequest) async throws -> Data {
        let (data, status) = try await transport.data(for: request)
        if status == 401 || status == 403 { throw RestaurantHTTPError.unauthorized }
        if status == 429 { throw RestaurantHTTPError.rateLimited }
        guard (200..<300).contains(status), !data.isEmpty else { throw RestaurantHTTPError.providerFailure(status) }
        return data
    }
}
