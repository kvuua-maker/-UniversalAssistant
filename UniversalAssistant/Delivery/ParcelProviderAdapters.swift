import Foundation

protocol ParcelHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, Int)
}

struct URLSessionParcelTransport: ParcelHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ParcelAdapterError.invalidResponse }
        return (data, http.statusCode)
    }
}

enum ParcelAdapterError: Error, Equatable {
    case missingCredential, invalidResponse, unauthorized, rateLimited, providerFailure(Int), noResult
}

struct ParcelProviderFactory {
    private let transport: any ParcelHTTPTransport

    init(transport: any ParcelHTTPTransport = URLSessionParcelTransport()) { self.transport = transport }

    func novaPoshta(apiKey: String) throws -> any ParcelDeliveryProvider {
        try NovaPoshtaParcelProvider(apiKey: required(apiKey), transport: transport)
    }

    func ukrposhta(bearerToken: String) throws -> any ParcelDeliveryProvider {
        OfficialParcelHTTPProvider(carrier: .ukrposhta,
            trackingEndpoint: URL(string: "https://www.ukrposhta.ua/status-tracking/0.0.1/statuses")!,
            branchesEndpoint: URL(string: "https://www.ukrposhta.ua/address-classifier-ws/get_postoffices_by_address")!,
            authorizationHeader: "Bearer \(try required(bearerToken))", transport: transport)
    }

    func meest(accessToken: String) throws -> any ParcelDeliveryProvider {
        OfficialParcelHTTPProvider(carrier: .meest,
            trackingEndpoint: URL(string: "https://mwl.meest.com/mwl/v2/api/tracking")!,
            branchesEndpoint: URL(string: "https://mwl.meest.com/mwl/v2/api/points")!,
            authorizationHeader: "Bearer \(try required(accessToken))", transport: transport)
    }

    private func required(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ParcelAdapterError.missingCredential }
        return trimmed
    }
}

struct OfficialParcelHTTPProvider: ParcelDeliveryProvider {
    let carrier: ParcelCarrier
    let trackingEndpoint: URL
    let branchesEndpoint: URL
    let authorizationHeader: String?
    let transport: any ParcelHTTPTransport

    init(carrier: ParcelCarrier, trackingEndpoint: URL, branchesEndpoint: URL,
         authorizationHeader: String?, transport: any ParcelHTTPTransport = URLSessionParcelTransport()) {
        self.carrier = carrier; self.trackingEndpoint = trackingEndpoint
        self.branchesEndpoint = branchesEndpoint; self.authorizationHeader = authorizationHeader
        self.transport = transport
    }

    func track(_ number: String) async throws -> ParcelTrackingResult {
        var components = URLComponents(url: trackingEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = (components.queryItems ?? []) + [.init(name: "trackingNumber", value: number)]
        var request = URLRequest(url: components.url!); request.timeoutInterval = 8
        if let authorizationHeader { request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization") }
        let (data, status) = try await transport.data(for: request)
        try validate(status)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = firstDictionary(object) else { throw ParcelAdapterError.noResult }
        let state = string(dictionary, keys: ["status", "Status", "statusName", "description"])
        let reference = string(dictionary, keys: ["eventId", "id", "ref", "RefEW"]) ?? number
        return .init(carrier: carrier, trackingNumber: number, status: state,
                     estimatedDelivery: nil, knowledge: state == nil ? .unknown : .confirmedEvent,
                     events: [], observedAt: .now,
                     sourceReference: carrier.rawValue + ":" + reference)
    }

    func branches(near latitude: Double, longitude: Double) async throws -> [ParcelBranch] {
        var components = URLComponents(url: branchesEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "latitude", value: String(latitude)),
                                 .init(name: "longitude", value: String(longitude))]
        var request = URLRequest(url: components.url!); request.timeoutInterval = 8
        if let authorizationHeader { request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization") }
        let (data, status) = try await transport.data(for: request)
        try validate(status)
        let object = try JSONSerialization.jsonObject(with: data)
        let rows = dictionaries(object)
        return rows.compactMap { row in
            guard let id = string(row, keys: ["id", "ref", "Ref"]),
                  let name = string(row, keys: ["name", "description", "Description"]),
                  let lat = number(row, keys: ["latitude", "lat", "Latitude"]),
                  let lon = number(row, keys: ["longitude", "lng", "Longitude"]) else { return nil }
            return .init(id: id, carrier: carrier, name: name, latitude: lat,
                         longitude: lon, sourceReference: carrier.rawValue + ":" + id)
        }
    }

    private func validate(_ status: Int) throws {
        if status == 401 || status == 403 { throw ParcelAdapterError.unauthorized }
        if status == 429 { throw ParcelAdapterError.rateLimited }
        guard (200..<300).contains(status) else { throw ParcelAdapterError.providerFailure(status) }
    }
    private func firstDictionary(_ value: Any) -> [String: Any]? { dictionaries(value).first }
    private func dictionaries(_ value: Any) -> [[String: Any]] {
        if let row = value as? [String: Any] {
            for key in ["data", "items", "results", "statuses"] {
                if let nested = row[key] { let found = dictionaries(nested); if !found.isEmpty { return found } }
            }
            return [row]
        }
        return (value as? [Any])?.flatMap(dictionaries) ?? []
    }
    private func string(_ row: [String: Any], keys: [String]) -> String? {
        keys.compactMap { row[$0] as? String }.first
    }
    private func number(_ row: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = row[key] as? Double { return value }
            if let text = row[key] as? String, let value = Double(text) { return value }
        }
        return nil
    }
}

struct ParcelWatch: Codable, Equatable, Sendable {
    let id: UUID
    let carrier: ParcelCarrier
    let trackingNumber: String
    let lastSourceReference: String?
    let expiresAt: Date
}

struct ParcelWatchPlanner {
    func create(carrier: ParcelCarrier, trackingNumber: String, now: Date = .now) throws -> ParcelWatch {
        guard trackingNumber.count >= 5 else { throw ParcelDeliveryError.invalidTrackingNumber }
        return .init(id: UUID(), carrier: carrier, trackingNumber: trackingNumber,
                     lastSourceReference: nil, expiresAt: now.addingTimeInterval(30 * 24 * 3600))
    }
    func changed(_ watch: ParcelWatch, result: ParcelTrackingResult, now: Date = .now) -> Bool {
        now < watch.expiresAt && watch.carrier == result.carrier &&
        watch.trackingNumber == result.trackingNumber &&
        watch.lastSourceReference != result.sourceReference
    }
}

struct NovaPoshtaParcelProvider: ParcelDeliveryProvider {
    let carrier: ParcelCarrier = .novaPoshta
    private let apiKey: String
    private let transport: any ParcelHTTPTransport
    private let endpoint = URL(string: "https://api.novaposhta.ua/v2.0/json/")!

    init(apiKey: String, transport: any ParcelHTTPTransport = URLSessionParcelTransport()) throws {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ParcelAdapterError.missingCredential
        }
        self.apiKey = apiKey; self.transport = transport
    }

    func track(_ number: String) async throws -> ParcelTrackingResult {
        let rows = try await call(model: "TrackingDocument", method: "getStatusDocuments",
                                  properties: ["Documents": [["DocumentNumber": number]]])
        guard let row = rows.first else { throw ParcelAdapterError.noResult }
        let status = row["Status"] as? String
        let reference = row["RefEW"] as? String ?? number
        return .init(carrier: carrier, trackingNumber: number, status: status,
                     estimatedDelivery: nil, knowledge: status == nil ? .unknown : .confirmedEvent,
                     events: [], observedAt: .now, sourceReference: "novaPoshta:" + reference)
    }

    func branches(near latitude: Double, longitude: Double) async throws -> [ParcelBranch] {
        let rows = try await call(model: "Address", method: "getWarehouses", properties: [:])
        return rows.compactMap { row in
            guard let id = row["Ref"] as? String, let name = row["Description"] as? String,
                  let lat = Double(row["Latitude"] as? String ?? ""),
                  let lon = Double(row["Longitude"] as? String ?? "") else { return nil }
            return .init(id: id, carrier: carrier, name: name, latitude: lat,
                         longitude: lon, sourceReference: "novaPoshta:" + id)
        }.sorted {
            hypot($0.latitude - latitude, $0.longitude - longitude) <
            hypot($1.latitude - latitude, $1.longitude - longitude)
        }
    }

    private func call(model: String, method: String, properties: [String: Any]) async throws -> [[String: Any]] {
        var request = URLRequest(url: endpoint); request.httpMethod = "POST"; request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "apiKey": apiKey, "modelName": model, "calledMethod": method,
            "methodProperties": properties
        ])
        let (data, status) = try await transport.data(for: request)
        if status == 429 { throw ParcelAdapterError.rateLimited }
        guard (200..<300).contains(status) else { throw ParcelAdapterError.providerFailure(status) }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["success"] as? Bool == true,
              let rows = object["data"] as? [[String: Any]] else { throw ParcelAdapterError.invalidResponse }
        return rows
    }
}
