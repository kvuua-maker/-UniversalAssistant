import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Decimal), bool(Bool), null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Decimal.self) { self = .number(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value") }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

public struct MCPHTTPResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data
    public init(statusCode: Int, headers: [String: String] = [:], body: Data) {
        self.statusCode = statusCode; self.headers = headers; self.body = body
    }
}

public protocol MCPHTTPTransport: Sendable {
    func execute(_ request: URLRequest) async throws -> MCPHTTPResponse
}

public struct URLSessionMCPTransport: MCPHTTPTransport {
    public init() {}
    public func execute(_ request: URLRequest) async throws -> MCPHTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SilpoMCPError.invalidResponse }
        let pairs: [(String, String)] = http.allHeaderFields.compactMap { key, value in
            guard let key = key as? String, let value = value as? String else { return nil }
            return (key.lowercased(), value)
        }
        let headers: [String: String] = Dictionary(uniqueKeysWithValues: pairs)
        return .init(statusCode: http.statusCode, headers: headers, body: data)
    }
}

public enum SilpoReadTool: String, CaseIterable, Sendable {
    case findProductsBatch = "silpo_find_products_batch"
    case getProducts = "silpo_get_products"
    case getProductDetails = "silpo_get_product_details"
    case getSimilarProducts = "silpo_get_similar_products"
    case getReplacements = "silpo_get_replacements"
    case getCategories = "silpo_get_categories"
    case getCategoriesTree = "silpo_get_categories_tree"
    case getPromotions = "silpo_get_promotions"
    case getAvailableDeliveryTypes = "silpo_get_available_delivery_types"
    case listBranches = "silpo_list_branches"
    case getTimeSlots = "silpo_get_time_slots"
    case getShoppingCart = "silpo_get_shopping_cart_by_id"
}

public struct MCPToolDescriptor: Codable, Equatable, Sendable {
    public let name: String
    public let description: String?
    public let inputSchema: JSONValue
}

public enum SilpoMCPError: Error, Equatable, Sendable {
    case invalidEndpoint, missingAccessToken, unauthorized, rateLimited, serverStatus(Int)
    case invalidResponse, protocolError(code: Int, message: String), toolNotAdvertised, writeToolForbidden
}

private struct JSONRPCRequest: Encodable {
    let jsonrpc = "2.0"
    let id: String
    let method: String
    let params: JSONValue?
}

private struct JSONRPCEnvelope: Decodable {
    struct Failure: Decodable { let code: Int; let message: String }
    let result: JSONValue?
    let error: Failure?
}

public actor SilpoMCPClient {
    public static let officialEndpoint = URL(string: "https://mcp.silpo.ua/mcp")!
    private let endpoint: URL
    private let transport: any MCPHTTPTransport
    private let timeout: TimeInterval
    private var advertisedTools: Set<String> = []

    public init(endpoint: URL = officialEndpoint, transport: any MCPHTTPTransport = URLSessionMCPTransport(), timeout: TimeInterval = 12) throws {
        guard endpoint.scheme == "https", endpoint.host == "mcp.silpo.ua", endpoint.path == "/mcp",
              endpoint.query == nil, timeout > 0, timeout <= 30 else { throw SilpoMCPError.invalidEndpoint }
        self.endpoint = endpoint; self.transport = transport; self.timeout = timeout
    }

    @discardableResult
    public func discoverTools(accessToken: String) async throws -> [MCPToolDescriptor] {
        let result = try await rpc(method: "tools/list", params: nil, accessToken: accessToken)
        guard case .object(let root) = result, case .array(let rawTools)? = root["tools"] else {
            throw SilpoMCPError.invalidResponse
        }
        let data = try JSONEncoder().encode(rawTools)
        let tools = try JSONDecoder().decode([MCPToolDescriptor].self, from: data)
        advertisedTools = Set(tools.map(\.name))
        return tools
    }

    public func call(_ tool: SilpoReadTool, arguments: [String: JSONValue], accessToken: String) async throws -> JSONValue {
        guard advertisedTools.contains(tool.rawValue) else { throw SilpoMCPError.toolNotAdvertised }
        return try await rpc(
            method: "tools/call",
            params: .object(["name": .string(tool.rawValue), "arguments": .object(arguments)]),
            accessToken: accessToken
        )
    }

    public func callToolNamed(_ name: String, arguments: [String: JSONValue], accessToken: String) async throws -> JSONValue {
        guard SilpoReadTool(rawValue: name) != nil else { throw SilpoMCPError.writeToolForbidden }
        return try await call(SilpoReadTool(rawValue: name)!, arguments: arguments, accessToken: accessToken)
    }

    private func rpc(method: String, params: JSONValue?, accessToken: String) async throws -> JSONValue {
        guard !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SilpoMCPError.missingAccessToken }
        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(JSONRPCRequest(id: UUID().uuidString, method: method, params: params))
        let response = try await transport.execute(request)
        switch response.statusCode {
        case 200...299: break
        case 401: throw SilpoMCPError.unauthorized
        case 429: throw SilpoMCPError.rateLimited
        default: throw SilpoMCPError.serverStatus(response.statusCode)
        }
        let payload = try Self.payload(from: response)
        let envelope = try JSONDecoder().decode(JSONRPCEnvelope.self, from: payload)
        if let error = envelope.error { throw SilpoMCPError.protocolError(code: error.code, message: error.message) }
        guard let result = envelope.result else { throw SilpoMCPError.invalidResponse }
        return result
    }

    private static func payload(from response: MCPHTTPResponse) throws -> Data {
        let contentType = response.headers["content-type"]?.lowercased() ?? "application/json"
        guard contentType.contains("text/event-stream") else { return response.body }
        guard let text = String(data: response.body, encoding: .utf8),
              let line = text.split(whereSeparator: \.isNewline).last(where: { $0.hasPrefix("data:") }) else {
            throw SilpoMCPError.invalidResponse
        }
        return Data(line.dropFirst(5).trimmingCharacters(in: .whitespaces).utf8)
    }
}
