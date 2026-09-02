import Foundation

protocol AppointmentHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, Int)
}
struct URLSessionAppointmentTransport: AppointmentHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw AppointmentHTTPError.invalidResponse }
        return (data, response.statusCode)
    }
}
enum AppointmentHTTPError: Error, Equatable {
    case missingCredential, invalidResponse, unauthorized, rateLimited, providerFailure(Int)
}

struct AppointmentProviderConfiguration: Sendable {
    let providerID: String
    let searchURL: URL
    let bookingURL: URL
}

struct OfficialAppointmentHTTPProvider: AppointmentProvider {
    let providerID: String
    private let searchURL: URL
    private let bookingURL: URL
    private let bearerToken: String
    private let transport: any AppointmentHTTPTransport

    init(configuration: AppointmentProviderConfiguration, bearerToken: String,
         transport: any AppointmentHTTPTransport = URLSessionAppointmentTransport()) throws {
        let token = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw AppointmentHTTPError.missingCredential }
        providerID = configuration.providerID; searchURL = configuration.searchURL
        bookingURL = configuration.bookingURL; self.bearerToken = token; self.transport = transport
    }

    func search(_ input: AppointmentSearchRequest) async throws -> [AppointmentSlot] {
        var request = base(searchURL, method: "POST")
        request.httpBody = try JSONEncoder().encode(input)
        let data = try await execute(request)
        return try JSONDecoder().decode([AppointmentSlot].self, from: data)
    }
    func book(slotID: String) async throws -> AppointmentBooking {
        try await mutation(path: "book", body: ["slot_id": slotID])
    }
    func reschedule(bookingID: String, slotID: String) async throws -> AppointmentBooking {
        try await mutation(path: "\(bookingID)/reschedule", body: ["slot_id": slotID])
    }
    func cancel(bookingID: String) async throws -> AppointmentBooking {
        try await mutation(path: "\(bookingID)/cancel", body: [:])
    }
    private func mutation(path: String, body: [String: String]) async throws -> AppointmentBooking {
        var request = base(bookingURL.appendingPathComponent(path), method: "POST")
        request.httpBody = try JSONEncoder().encode(body)
        return try JSONDecoder().decode(AppointmentBooking.self, from: await execute(request))
    }
    private func base(_ url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url); request.httpMethod = method; request.timeoutInterval = 8
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
    private func execute(_ request: URLRequest) async throws -> Data {
        let (data, status) = try await transport.data(for: request)
        if status == 401 || status == 403 { throw AppointmentHTTPError.unauthorized }
        if status == 429 { throw AppointmentHTTPError.rateLimited }
        guard (200..<300).contains(status), !data.isEmpty else { throw AppointmentHTTPError.providerFailure(status) }
        return data
    }
}
