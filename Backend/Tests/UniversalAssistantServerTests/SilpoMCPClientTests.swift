import Foundation
import Testing
@testable import UniversalAssistantServer

private actor MCPTransportStub: MCPHTTPTransport {
    var requests: [URLRequest] = []
    let responses: [MCPHTTPResponse]
    private var index = 0
    init(_ responses: [MCPHTTPResponse]) { self.responses = responses }
    func execute(_ request: URLRequest) async throws -> MCPHTTPResponse {
        requests.append(request)
        defer { index += 1 }
        return responses[index]
    }
}

private func response(_ json: String, contentType: String = "application/json") -> MCPHTTPResponse {
    .init(statusCode: 200, headers: ["content-type": contentType], body: Data(json.utf8))
}

@Suite("Official Silpo MCP read adapter") struct SilpoMCPClientTests {
    @Test func discoversThenCallsOnlyAdvertisedReadTool() async throws {
        let transport = MCPTransportStub([
            response(#"{"jsonrpc":"2.0","id":"1","result":{"tools":[{"name":"silpo_get_products","description":"Products","inputSchema":{"type":"object"}}]}}"#),
            response(#"{"jsonrpc":"2.0","id":"2","result":{"content":[]}}"#)
        ])
        let client = try SilpoMCPClient(transport: transport)
        let tools = try await client.discoverTools(accessToken: "runtime-token")
        #expect(tools.map(\.name) == ["silpo_get_products"])
        _ = try await client.call(.getProducts, arguments: ["query": .string("молоко")], accessToken: "runtime-token")
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.url == SilpoMCPClient.officialEndpoint })
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer runtime-token" })
    }

    @Test func writeAndUndiscoveredToolsFailBeforeNetwork() async throws {
        let transport = MCPTransportStub([])
        let client = try SilpoMCPClient(transport: transport)
        await #expect(throws: SilpoMCPError.writeToolForbidden) {
            try await client.callToolNamed("silpo_add_or_update_cart_products", arguments: [:], accessToken: "token")
        }
        await #expect(throws: SilpoMCPError.toolNotAdvertised) {
            try await client.call(.getProducts, arguments: [:], accessToken: "token")
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test func parsesStreamableHTTPEventAndMapsAuthWithoutLeakingToken() async throws {
        let sse = "event: message\ndata: {\"jsonrpc\":\"2.0\",\"id\":\"1\",\"result\":{\"tools\":[]}}\n\n"
        let transport = MCPTransportStub([response(sse, contentType: "text/event-stream")])
        let client = try SilpoMCPClient(transport: transport)
        #expect(try await client.discoverTools(accessToken: "super-secret").isEmpty)

        let unauthorized = MCPTransportStub([.init(statusCode: 401, body: Data("super-secret".utf8))])
        let deniedClient = try SilpoMCPClient(transport: unauthorized)
        await #expect(throws: SilpoMCPError.unauthorized) {
            try await deniedClient.discoverTools(accessToken: "super-secret")
        }
    }

    @Test func rejectsAnyEndpointVariation() {
        #expect(throws: SilpoMCPError.invalidEndpoint) {
            try SilpoMCPClient(endpoint: URL(string: "https://mcp.silpo.ua/")!, transport: MCPTransportStub([]))
        }
    }
}
