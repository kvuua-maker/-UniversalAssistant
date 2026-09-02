import Foundation

public struct APNSPayload: Codable, Equatable, Sendable {
    public struct APS: Codable, Equatable, Sendable {
        public let alert: String
        public let sound: String?
        public let threadID: String
        enum CodingKeys: String, CodingKey { case alert, sound; case threadID = "thread-id" }
        public init(alert: String, sound: String? = nil, threadID: String) {
            self.alert = alert; self.sound = sound; self.threadID = threadID
        }
    }
    public let aps: APS
    public let route: String
    public init(aps: APS, route: String) { self.aps = aps; self.route = route }
}

public struct APNSRequest: Equatable, Sendable {
    public let url: URL
    public let headers: [String: String]
    public let body: Data
}

public struct APNSHTTPResponse: Equatable, Sendable {
    public let statusCode: Int
    public let apnsID: String?
    public let reason: String?
    public init(statusCode: Int, apnsID: String? = nil, reason: String? = nil) {
        self.statusCode = statusCode; self.apnsID = apnsID; self.reason = reason
    }
}

public enum APNSDeliveryOutcome: Equatable, Sendable {
    case accepted(apnsID: String?)
    case invalidToken
    case retryable(statusCode: Int)
    case rejected(statusCode: Int, reason: String)
}

public enum APNSDeliveryError: Error, Equatable, Sendable {
    case invalidConfiguration, invalidPayload, missingAuthorization
}

public protocol APNSTransport: Sendable {
    func send(_ request: APNSRequest) async throws -> APNSHTTPResponse
}

public struct APNSDeliveryClient: Sendable {
    public let topic: String
    public let authorization: String?
    public let transport: any APNSTransport

    public init(topic: String, authorization: String?, transport: any APNSTransport) {
        self.topic = topic; self.authorization = authorization; self.transport = transport
    }

    public func deliver(payload: APNSPayload, registration: APNSDeviceRegistration,
                        collapseID: String, expiresAt: Date, now: Date = .now) async throws -> APNSDeliveryOutcome {
        guard !topic.isEmpty, !collapseID.isEmpty, collapseID.utf8.count <= 64,
              expiresAt > now else { throw APNSDeliveryError.invalidConfiguration }
        guard let authorization, authorization.hasPrefix("bearer "), authorization.count > 10 else {
            throw APNSDeliveryError.missingAuthorization
        }
        let body = try JSONEncoder().encode(payload)
        guard !payload.aps.alert.isEmpty, body.count <= 4_096,
              payload.route.hasPrefix("universalassistant://open/") else { throw APNSDeliveryError.invalidPayload }
        let host = registration.environment == .production ? "api.push.apple.com" : "api.sandbox.push.apple.com"
        let token = registration.token.map { String(format: "%02x", $0) }.joined()
        let request = APNSRequest(url: URL(string: "https://\(host)/3/device/\(token)")!, headers: [
            "authorization": authorization, "apns-topic": topic, "apns-push-type": "alert",
            "apns-priority": "10", "apns-expiration": String(Int(expiresAt.timeIntervalSince1970)),
            "apns-collapse-id": collapseID
        ], body: body)
        return classify(try await transport.send(request))
    }

    private func classify(_ response: APNSHTTPResponse) -> APNSDeliveryOutcome {
        if response.statusCode == 200 { return .accepted(apnsID: response.apnsID) }
        if response.statusCode == 410 || response.reason == "Unregistered" || response.reason == "BadDeviceToken" {
            return .invalidToken
        }
        if response.statusCode == 429 || response.statusCode >= 500 { return .retryable(statusCode: response.statusCode) }
        return .rejected(statusCode: response.statusCode, reason: String((response.reason ?? "apns_rejected").prefix(80)))
    }
}
