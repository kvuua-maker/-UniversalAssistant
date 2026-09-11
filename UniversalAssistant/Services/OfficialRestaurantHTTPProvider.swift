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
    let modificationURL: URL?
    let cancellationURL: URL?

    init(
        providerID: String,
        availabilityURL: URL,
        bookingURL: URL,
        modificationURL: URL? = nil,
        cancellationURL: URL? = nil
    ) {
        self.providerID = providerID
        self.availabilityURL = availabilityURL
        self.bookingURL = bookingURL
        self.modificationURL = modificationURL
        self.cancellationURL = cancellationURL
    }
}

struct OfficialRestaurantHTTPProvider: ReservationProvider {
    let providerID: String
    private let availabilityURL: URL
    private let bookingURL: URL
    private let modificationURL: URL?
    private let cancellationURL: URL?
    private let bearerToken: String
    private let transport: any RestaurantHTTPTransport

    init(configuration: RestaurantProviderConfiguration, bearerToken: String,
         transport: any RestaurantHTTPTransport = URLSessionRestaurantTransport()) throws {
        let token = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw RestaurantHTTPError.missingCredential }
        let optionalURLs = [configuration.modificationURL, configuration.cancellationURL].compactMap { $0 }
        guard configuration.availabilityURL.scheme == "https", configuration.bookingURL.scheme == "https",
              optionalURLs.allSatisfy({ $0.scheme == "https" }),
              !configuration.providerID.isEmpty else { throw RestaurantHTTPError.invalidConfiguration }
        providerID = configuration.providerID
        availabilityURL = configuration.availabilityURL
        bookingURL = configuration.bookingURL
        modificationURL = configuration.modificationURL
        cancellationURL = configuration.cancellationURL
        self.bearerToken = token
        self.transport = transport
    }

    var capabilities: Set<RestaurantProviderCapability> {
        var values: Set<RestaurantProviderCapability> = [.availability, .booking]
        if modificationURL != nil { values.insert(.modification) }
        if cancellationURL != nil { values.insert(.cancellation) }
        return values
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

    func modify(bookingID: String, slotID: String) async throws -> RestaurantReservation {
        guard let modificationURL else { throw RestaurantDiscoveryError.providerOperationUnavailable }
        struct Body: Encodable { let bookingID: String; let slotID: String }
        var request = base(modificationURL)
        request.httpBody = try JSONEncoder().encode(Body(bookingID: bookingID, slotID: slotID))
        return try JSONDecoder().decode(RestaurantReservation.self, from: await execute(request))
    }

    func cancel(bookingID: String) async throws -> RestaurantReservation {
        guard let cancellationURL else { throw RestaurantDiscoveryError.providerOperationUnavailable }
        struct Body: Encodable { let bookingID: String }
        var request = base(cancellationURL)
        request.httpBody = try JSONEncoder().encode(Body(bookingID: bookingID))
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
