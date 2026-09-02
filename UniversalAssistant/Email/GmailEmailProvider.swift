import Foundation

struct EmailMessageSummary: Identifiable, Equatable, Sendable {
    let id: String
    let threadID: String
}

struct EmailMessage: Equatable, Sendable {
    let id: String
    let threadID: String
    let snippet: String
    let rawPayload: Data?
}

struct EmailDraftRequest: Equatable, Sendable {
    let rawRFC2822: Data
    let threadID: String?
}

enum EmailMutation: Equatable, Sendable { case addLabels(Set<String>), removeLabels(Set<String>), trash }

protocol EmailProvider: Sendable {
    func search(query: String, limit: Int) async throws -> [EmailMessageSummary]
    func message(id: String) async throws -> EmailMessage
    func attachment(messageID: String, attachmentID: String) async throws -> Data
    func createDraft(_ request: EmailDraftRequest) async throws -> String
    func sendReply(_ request: EmailDraftRequest, confirmed: Bool) async throws -> String
    func mutate(messageID: String, mutation: EmailMutation, confirmed: Bool) async throws
}

struct EmailHTTPResponse: Sendable { let status: Int; let data: Data }
protocol EmailHTTPTransport: Sendable { func execute(_ request: URLRequest) async throws -> EmailHTTPResponse }

struct URLSessionEmailTransport: EmailHTTPTransport {
    func execute(_ request: URLRequest) async throws -> EmailHTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GmailError.invalidResponse }
        return .init(status: http.statusCode, data: data)
    }
}

enum GmailError: Error, Equatable { case invalidInput, confirmationRequired, invalidResponse, http(Int) }

struct GmailEmailProvider: EmailProvider {
    private let token: String
    private let transport: any EmailHTTPTransport
    private let baseURL = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me")!

    init(accessToken: String, transport: any EmailHTTPTransport = URLSessionEmailTransport()) throws {
        guard !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GmailError.invalidInput }
        token = accessToken; self.transport = transport
    }

    func search(query: String, limit: Int) async throws -> [EmailMessageSummary] {
        guard !query.isEmpty else { throw GmailError.invalidInput }
        var components = URLComponents(url: baseURL.appending(path: "messages"), resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "q", value: query), .init(name: "maxResults", value: String(max(1, min(limit, 25))))]
        let value: MessageList = try await send(url: components.url!)
        return (value.messages ?? []).map { .init(id: $0.id, threadID: $0.threadId) }
    }

    func message(id: String) async throws -> EmailMessage {
        let value: MessageWire = try await send(url: try endpoint("messages", id, query: [.init(name: "format", value: "raw")]))
        return .init(id: value.id, threadID: value.threadId, snippet: value.snippet ?? "",
                     rawPayload: value.raw.flatMap(Self.decodeBase64URL))
    }

    func attachment(messageID: String, attachmentID: String) async throws -> Data {
        let value: AttachmentWire = try await send(url: try endpoint("messages", messageID, "attachments", attachmentID))
        guard let data = Self.decodeBase64URL(value.data) else { throw GmailError.invalidResponse }
        return data
    }

    func createDraft(_ request: EmailDraftRequest) async throws -> String {
        let wire = DraftRequestWire(message: .init(raw: Self.base64URL(request.rawRFC2822), threadId: request.threadID))
        let value: DraftWire = try await send(url: baseURL.appending(path: "drafts"), method: "POST", body: wire)
        return value.id
    }

    func sendReply(_ request: EmailDraftRequest, confirmed: Bool) async throws -> String {
        guard confirmed else { throw GmailError.confirmationRequired }
        let wire = MessageRequestWire(raw: Self.base64URL(request.rawRFC2822), threadId: request.threadID)
        let value: MessageWire = try await send(url: baseURL.appending(path: "messages/send"), method: "POST", body: wire)
        return value.id
    }

    func mutate(messageID: String, mutation: EmailMutation, confirmed: Bool) async throws {
        guard confirmed else { throw GmailError.confirmationRequired }
        switch mutation {
        case .trash:
            let _: MessageWire = try await send(url: try endpoint("messages", messageID, "trash"), method: "POST", body: Empty())
        case let .addLabels(labels):
            let _: MessageWire = try await send(url: try endpoint("messages", messageID, "modify"), method: "POST", body: Modify(addLabelIds: Array(labels).sorted(), removeLabelIds: []))
        case let .removeLabels(labels):
            let _: MessageWire = try await send(url: try endpoint("messages", messageID, "modify"), method: "POST", body: Modify(addLabelIds: [], removeLabelIds: Array(labels).sorted()))
        }
    }

    private func endpoint(_ parts: String..., query: [URLQueryItem] = []) throws -> URL {
        guard parts.allSatisfy({ !$0.isEmpty && !$0.contains("/") }) else { throw GmailError.invalidInput }
        var components = URLComponents(url: parts.reduce(baseURL) { $0.appending(path: $1) }, resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        return components.url!
    }

    private func send<Response: Decodable>(url: URL, method: String = "GET") async throws -> Response {
        try await send(url: url, method: method, bodyData: nil)
    }
    private func send<Response: Decodable, Body: Encodable>(url: URL, method: String, body: Body) async throws -> Response {
        try await send(url: url, method: method, bodyData: try JSONEncoder().encode(body))
    }
    private func send<Response: Decodable>(url: URL, method: String, bodyData: Data?) async throws -> Response {
        var request = URLRequest(url: url); request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let bodyData { request.httpBody = bodyData; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let response = try await transport.execute(request)
        guard (200..<300).contains(response.status) else { throw GmailError.http(response.status) }
        do { return try JSONDecoder().decode(Response.self, from: response.data) }
        catch { throw GmailError.invalidResponse }
    }

    private static func base64URL(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    private static func decodeBase64URL(_ value: String) -> Data? {
        var padded = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        padded += String(repeating: "=", count: (4 - padded.count % 4) % 4)
        return Data(base64Encoded: padded)
    }
}

private struct MessageList: Decodable { let messages: [MessageWire]? }
private struct MessageWire: Codable { let id: String; let threadId: String; var snippet: String? = nil; var raw: String? = nil }
private struct AttachmentWire: Decodable { let data: String }
private struct DraftWire: Decodable { let id: String }
private struct DraftRequestWire: Encodable { let message: MessageRequestWire }
private struct MessageRequestWire: Codable { let raw: String; let threadId: String? }
private struct Modify: Encodable { let addLabelIds: [String]; let removeLabelIds: [String] }
private struct Empty: Codable {}
