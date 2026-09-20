import Foundation
import AuthenticationServices
import CryptoKit
import Security
import Observation
import UIKit

enum SilpoConnectionError: Error, Equatable {
    case invalidMetadata, invalidRegistration, invalidCallback, cancelled, unauthorized, toolUnavailable, malformedResponse
}

private enum SilpoJSON: Codable, Equatable, Sendable {
    case object([String: SilpoJSON]), array([SilpoJSON]), string(String), number(Decimal), bool(Bool), null
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let object = try? value.decode([String: SilpoJSON].self) { self = .object(object) }
        else if let array = try? value.decode([SilpoJSON].self) { self = .array(array) }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else if let number = try? value.decode(Decimal.self) { self = .number(number) }
        else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else { throw SilpoConnectionError.malformedResponse }
    }
    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self { case .object(let x): try value.encode(x); case .array(let x): try value.encode(x); case .string(let x): try value.encode(x); case .number(let x): try value.encode(x); case .bool(let x): try value.encode(x); case .null: try value.encodeNil() }
    }
}

private struct SilpoCredential: Codable, Sendable {
    let clientID: String
    let accessToken: String
    let refreshToken: String?
    let tokenEndpoint: URL
    let expiresAt: Date
    let scope: String?
}

private struct SilpoPendingAuthorization: Sendable {
    let authorizationURL: URL
    let tokenEndpoint: URL
    let clientID: String
    let verifier: String
    let state: String
}

enum SilpoOAuthSecurity {
    static func pkceChallenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }

    static func authorizationCode(from callback: URL, expectedState: String) throws -> String {
        guard callback.scheme == SilpoOAuthMCPService.callback.scheme,
              callback.host == SilpoOAuthMCPService.callback.host,
              let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              components.queryItems?.first(where: { $0.name == "state" })?.value == expectedState,
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else { throw SilpoConnectionError.invalidCallback }
        return code
    }
}

actor SilpoOAuthMCPService {
    static let shared = SilpoOAuthMCPService()
    static let endpoint = URL(string: "https://mcp.silpo.ua/mcp")!
    static let callback = URL(string: "universalassistant://oauth/silpo")!

    private let session: URLSession
    private let keychain = SilpoCredentialKeychain()
    private var credential: SilpoCredential?
    private var tools: [Tool] = []

    init(session: URLSession = .shared) { self.session = session }

    func isConnected(now: Date = .now) -> Bool {
        if credential == nil { credential = try? keychain.load() }
        return credential?.expiresAt ?? .distantPast > now
    }

    fileprivate func prepareAuthorization() async throws -> SilpoPendingAuthorization {
        let protected = try await firstDecoded(ProtectedResource.self, urls: [
            URL(string: "https://mcp.silpo.ua/.well-known/oauth-protected-resource/mcp")!,
            URL(string: "https://mcp.silpo.ua/.well-known/oauth-protected-resource")!
        ])
        guard let issuer = protected.authorizationServers?.first else { throw SilpoConnectionError.invalidMetadata }
        let metadataURL = issuer.appendingPathComponent(".well-known/oauth-authorization-server")
        let metadata: AuthorizationMetadata = try await get(metadataURL)
        guard let registration = metadata.registrationEndpoint else { throw SilpoConnectionError.invalidMetadata }
        var request = URLRequest(url: registration, timeoutInterval: 10); request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RegistrationRequest(
            redirectUris: [Self.callback], clientName: "UniversalAssistant iOS",
            grantTypes: ["authorization_code", "refresh_token"], responseTypes: ["code"], tokenEndpointAuthMethod: "none"
        ))
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw SilpoConnectionError.invalidRegistration }
        let client = try JSONDecoder().decode(RegistrationResponse.self, from: data)
        let verifier = Self.randomURLSafe(bytes: 48), state = Self.randomURLSafe(bytes: 24)
        let challenge = SilpoOAuthSecurity.pkceChallenge(for: verifier)
        var components = URLComponents(url: metadata.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "response_type", value: "code"), .init(name: "client_id", value: client.clientID),
            .init(name: "redirect_uri", value: Self.callback.absoluteString), .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"), .init(name: "state", value: state)
        ]
        if let scopes = metadata.scopesSupported, !scopes.isEmpty { components.queryItems?.append(.init(name: "scope", value: scopes.joined(separator: " "))) }
        guard let url = components.url else { throw SilpoConnectionError.invalidMetadata }
        return .init(authorizationURL: url, tokenEndpoint: metadata.tokenEndpoint, clientID: client.clientID, verifier: verifier, state: state)
    }

    fileprivate func completeAuthorization(_ callback: URL, pending: SilpoPendingAuthorization) async throws {
        let code = try SilpoOAuthSecurity.authorizationCode(from: callback, expectedState: pending.state)
        var request = URLRequest(url: pending.tokenEndpoint, timeoutInterval: 10); request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents(); body.queryItems = [
            .init(name: "grant_type", value: "authorization_code"), .init(name: "code", value: code),
            .init(name: "client_id", value: pending.clientID), .init(name: "redirect_uri", value: Self.callback.absoluteString),
            .init(name: "code_verifier", value: pending.verifier)
        ]
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        let token: TokenResponse = try await performTokenRequest(request)
        let stored = SilpoCredential(clientID: pending.clientID, accessToken: token.accessToken, refreshToken: token.refreshToken,
                                     tokenEndpoint: pending.tokenEndpoint, expiresAt: .now.addingTimeInterval(TimeInterval(token.expiresIn ?? 3600)), scope: token.scope)
        try keychain.save(stored); credential = stored; tools = try await discoverTools(accessToken: stored.accessToken)
    }

    func disconnect() throws { try keychain.delete(); credential = nil; tools = [] }

    func searchOffers(_ request: RetailSearchRequest) async throws -> [NormalizedOffer] {
        let credential = try await validCredential()
        if tools.isEmpty { tools = try await discoverTools(accessToken: credential.accessToken) }
        guard let tool = tools.first(where: { $0.name == "silpo_find_products_batch" }) else { throw SilpoConnectionError.toolUnavailable }
        let query = [request.identity.brand, request.identity.model, request.identity.productType, request.identity.variant.size]
            .compactMap { $0 }.joined(separator: " ")
        guard let arguments = tool.arguments(for: query) else { throw SilpoConnectionError.toolUnavailable }
        let result = try await rpc(method: "tools/call", params: .object(["name": .string(tool.name), "arguments": .object(arguments)]), token: credential.accessToken)
        return SilpoOfferDecoder.decode(result, request: request)
    }

    private func validCredential() async throws -> SilpoCredential {
        let loaded = try keychain.load()
        let value = credential ?? loaded
        guard var current = value else { throw SilpoConnectionError.unauthorized }
        if current.expiresAt.timeIntervalSinceNow < 60, let refresh = current.refreshToken {
            var request = URLRequest(url: current.tokenEndpoint, timeoutInterval: 10); request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var body = URLComponents(); body.queryItems = [.init(name: "grant_type", value: "refresh_token"), .init(name: "refresh_token", value: refresh), .init(name: "client_id", value: current.clientID)]
            request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
            let token: TokenResponse = try await performTokenRequest(request)
            current = .init(clientID: current.clientID, accessToken: token.accessToken, refreshToken: token.refreshToken ?? refresh,
                            tokenEndpoint: current.tokenEndpoint, expiresAt: .now.addingTimeInterval(TimeInterval(token.expiresIn ?? 3600)), scope: token.scope ?? current.scope)
            try keychain.save(current); credential = current
        }
        guard current.expiresAt > .now else { throw SilpoConnectionError.unauthorized }
        return current
    }

    private func discoverTools(accessToken: String) async throws -> [Tool] {
        let result = try await rpc(method: "tools/list", params: nil, token: accessToken)
        guard case .object(let root) = result, case .array(let raw)? = root["tools"] else { throw SilpoConnectionError.malformedResponse }
        return try raw.map { value in try JSONDecoder().decode(Tool.self, from: JSONEncoder().encode(value)) }
    }

    private func rpc(method: String, params: SilpoJSON?, token: String) async throws -> SilpoJSON {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 10); request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(RPCRequest(id: UUID().uuidString, method: method, params: params))
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SilpoConnectionError.malformedResponse }
        guard http.statusCode != 401 else { throw SilpoConnectionError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw SilpoConnectionError.malformedResponse }
        let payload = http.value(forHTTPHeaderField: "Content-Type")?.contains("text/event-stream") == true
            ? Self.ssePayload(data) : data
        let envelope = try JSONDecoder().decode(RPCEnvelope.self, from: payload)
        guard envelope.error == nil, let result = envelope.result else { throw SilpoConnectionError.malformedResponse }
        return result
    }

    private func performTokenRequest(_ request: URLRequest) async throws -> TokenResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw SilpoConnectionError.unauthorized }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw SilpoConnectionError.invalidMetadata }
        return try JSONDecoder().decode(T.self, from: data)
    }
    private func firstDecoded<T: Decodable>(_ type: T.Type, urls: [URL]) async throws -> T {
        for url in urls { if let value: T = try? await get(url) { return value } }
        throw SilpoConnectionError.invalidMetadata
    }
    private static func randomURLSafe(bytes: Int) -> String { Data((0..<bytes).map { _ in UInt8.random(in: 0...255) }).base64URLEncodedString() }
    private static func ssePayload(_ data: Data) -> Data {
        guard let text = String(data: data, encoding: .utf8), let line = text.split(whereSeparator: \.isNewline).last(where: { $0.hasPrefix("data:") }) else { return data }
        return Data(line.dropFirst(5).trimmingCharacters(in: .whitespaces).utf8)
    }

    private struct ProtectedResource: Decodable { let authorizationServers: [URL]?; enum CodingKeys: String, CodingKey { case authorizationServers = "authorization_servers" } }
    private struct AuthorizationMetadata: Decodable {
        let authorizationEndpoint: URL; let tokenEndpoint: URL; let registrationEndpoint: URL?; let scopesSupported: [String]?
        enum CodingKeys: String, CodingKey { case authorizationEndpoint = "authorization_endpoint", tokenEndpoint = "token_endpoint", registrationEndpoint = "registration_endpoint", scopesSupported = "scopes_supported" }
    }
    private struct RegistrationRequest: Encodable {
        let redirectUris: [URL]; let clientName: String; let grantTypes: [String]; let responseTypes: [String]; let tokenEndpointAuthMethod: String
        enum CodingKeys: String, CodingKey { case redirectUris = "redirect_uris", clientName = "client_name", grantTypes = "grant_types", responseTypes = "response_types", tokenEndpointAuthMethod = "token_endpoint_auth_method" }
    }
    private struct RegistrationResponse: Decodable { let clientID: String; enum CodingKeys: String, CodingKey { case clientID = "client_id" } }
    private struct TokenResponse: Decodable {
        let accessToken: String; let refreshToken: String?; let expiresIn: Int?; let scope: String?
        enum CodingKeys: String, CodingKey { case accessToken = "access_token", refreshToken = "refresh_token", expiresIn = "expires_in", scope }
    }
    private struct RPCRequest: Encodable { let jsonrpc = "2.0"; let id: String; let method: String; let params: SilpoJSON? }
    private struct RPCEnvelope: Decodable { let result: SilpoJSON?; let error: SilpoJSON? }
    private struct Tool: Codable, Sendable {
        let name: String; let inputSchema: SilpoJSON
        enum CodingKeys: String, CodingKey { case name, inputSchema = "inputSchema" }
        func arguments(for query: String) -> [String: SilpoJSON]? {
            guard case .object(let schema) = inputSchema, case .object(let properties)? = schema["properties"] else { return nil }
            if properties["queries"] != nil { return ["queries": .array([.string(query)])] }
            if properties["query"] != nil { return ["query": .string(query)] }
            if properties["search"] != nil { return ["search": .string(query)] }
            return nil
        }
    }
}

struct SilpoRetailProvider: RetailProvider {
    let providerID = "silpo-mcp"
    let service: SilpoOAuthMCPService
    init(service: SilpoOAuthMCPService = .shared) { self.service = service }
    func search(_ request: RetailSearchRequest) async throws -> [NormalizedOffer] {
        guard await service.isConnected() else { return [] }
        return try await service.searchOffers(request)
    }
}

@MainActor @Observable
final class SilpoConnectionModel: NSObject, ASWebAuthenticationPresentationContextProviding {
    var connected = false
    var busy = false
    var message: String?
    private let service = SilpoOAuthMCPService.shared
    private var session: ASWebAuthenticationSession?

    func refresh() { Task { connected = await service.isConnected() } }
    func connect() {
        guard !busy else { return }; busy = true; message = nil
        Task {
            do {
                let pending = try await service.prepareAuthorization()
                let callback = try await authorize(pending.authorizationURL)
                try await service.completeAuthorization(callback, pending: pending)
                connected = true; message = "Сільпо підключено"
            } catch { message = error is CancellationError ? "Вхід скасовано" : "Не вдалося підключити Сільпо" }
            busy = false
        }
    }
    func disconnect() { Task { do { try await service.disconnect(); connected = false; message = nil } catch { message = "Не вдалося відключити Сільпо" } } }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }
    private func authorize(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: SilpoOAuthMCPService.callback.scheme) { callback, error in
                if let callback { continuation.resume(returning: callback) }
                else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { continuation.resume(throwing: CancellationError()) }
                else { continuation.resume(throwing: error ?? SilpoConnectionError.invalidCallback) }
            }
            session.presentationContextProvider = self; session.prefersEphemeralWebBrowserSession = false; self.session = session
            guard session.start() else { continuation.resume(throwing: SilpoConnectionError.invalidCallback); return }
        }
    }
}

private final class SilpoCredentialKeychain: @unchecked Sendable {
    private let service = "com.universalassistant.silpo.oauth", account = "current-user"
    func save(_ value: SilpoCredential) throws {
        let data = try JSONEncoder().encode(value); SecItemDelete(query() as CFDictionary)
        var attributes = query(); attributes[kSecValueData as String] = data; attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else { throw SilpoConnectionError.unauthorized }
    }
    func load() throws -> SilpoCredential? {
        var value = query(); value[kSecReturnData as String] = true; value[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?; let status = SecItemCopyMatching(value as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw SilpoConnectionError.unauthorized }
        return try JSONDecoder().decode(SilpoCredential.self, from: data)
    }
    func delete() throws { let status = SecItemDelete(query() as CFDictionary); guard status == errSecSuccess || status == errSecItemNotFound else { throw SilpoConnectionError.unauthorized } }
    private func query() -> [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] }
}

private enum SilpoOfferDecoder {
    static func decode(_ value: SilpoJSON, request: RetailSearchRequest) -> [NormalizedOffer] {
        objects(in: value).compactMap { object in
            guard let name = string(object, keys: ["name", "title", "product_name"]),
                  let price = number(object, keys: ["price", "current_price"]),
                  let urlText = string(object, keys: ["url", "product_url"]), let url = URL(string: urlText) else { return nil }
            let currency = string(object, keys: ["currency", "price_currency"]) ?? "UAH"
            let identity = ProductIdentity(brand: string(object, keys: ["brand"]), model: name,
                                           productType: request.identity.productType, sku: string(object, keys: ["sku", "id"]),
                                           gtin: string(object, keys: ["gtin", "barcode"]), variant: request.identity.variant)
            let match = ProductIdentityResolver().match(query: request.identity, candidate: identity)
            guard match.level != .unrelated else { return nil }
            return .init(id: "silpo:\(string(object, keys: ["id", "sku"]) ?? UUID().uuidString)", providerID: "silpo-mcp",
                         providerOfferID: string(object, keys: ["id", "sku"]) ?? UUID().uuidString,
                         identity: identity, identityMatch: match,
                         seller: .init(id: "silpo", name: "Сільпо", isOfficialStore: true),
                         availability: bool(object, keys: ["available", "in_stock"]) == false ? .outOfStock : .unknown,
                         cost: .init(item: .init(amount: price, currency: currency), shipping: .init(value: nil, knowledge: .unknown), tax: .init(value: nil, knowledge: .unknown), duties: .init(value: nil, knowledge: .unknown), requiredOther: .init(value: nil, knowledge: .unknown)),
                         deliversToUkraine: true, exactPurchaseURL: url, sourceTimestamp: .now, fetchedAt: .now,
                         affiliateAttributionSupported: false, imageURL: string(object, keys: ["image", "image_url"]).flatMap(URL.init(string:)),
                         sourceConfidence: .verifiedPartner, sourceProvenance: ["Silpo official MCP"])
        }
    }
    private static func objects(in value: SilpoJSON) -> [[String: SilpoJSON]] {
        switch value { case .object(let object): return [object] + object.values.flatMap(objects); case .array(let values): return values.flatMap(objects); default: return [] }
    }
    private static func string(_ object: [String: SilpoJSON], keys: [String]) -> String? { for key in keys { if case .string(let value)? = object[key] { return value } }; return nil }
    private static func number(_ object: [String: SilpoJSON], keys: [String]) -> Decimal? { for key in keys { if case .number(let value)? = object[key] { return value } }; return nil }
    private static func bool(_ object: [String: SilpoJSON], keys: [String]) -> Bool? { for key in keys { if case .bool(let value)? = object[key] { return value } }; return nil }
}

private extension Data {
    func base64URLEncodedString() -> String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}
