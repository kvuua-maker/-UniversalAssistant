import Foundation
import Testing
@testable import UniversalAssistant

private actor EmailTransportSpy: EmailHTTPTransport {
    var responses: [EmailHTTPResponse]
    var requests: [URLRequest] = []
    init(_ responses: [EmailHTTPResponse]) { self.responses = responses }
    func execute(_ request: URLRequest) throws -> EmailHTTPResponse { requests.append(request); return responses.removeFirst() }
}

@Suite("Gmail email provider") struct GmailEmailProviderTests {
    @Test func searchUsesOfficialEndpointAndBoundedProviderQuery() async throws {
        let transport = EmailTransportSpy([.init(status: 200, data: Data(#"{"messages":[{"id":"m1","threadId":"t1"}]}"#.utf8))])
        let provider = try GmailEmailProvider(accessToken: "token", transport: transport)
        #expect(try await provider.search(query: "from:dentist after:2026/07/01", limit: 100).map(\.id) == ["m1"])
        let request = try #require(await transport.requests.first)
        #expect(request.url?.host == "gmail.googleapis.com")
        #expect(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "maxResults" }?.value == "25")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
    }

    @Test func attachmentDecodesRealBase64URLPayload() async throws {
        let transport = EmailTransportSpy([.init(status: 200, data: Data(#"{"data":"aGVsbG8"}"#.utf8))])
        let provider = try GmailEmailProvider(accessToken: "token", transport: transport)
        #expect(try await provider.attachment(messageID: "m", attachmentID: "a") == Data("hello".utf8))
    }

    @Test func selectedMessageReturnsActualRawMIMEPayload() async throws {
        let transport = EmailTransportSpy([.init(status: 200, data: Data(#"{"id":"m","threadId":"t","raw":"U3ViamVjdDogVGlja2V0"}"#.utf8))])
        let provider = try GmailEmailProvider(accessToken: "token", transport: transport)
        let message = try await provider.message(id: "m")
        #expect(message.rawPayload == Data("Subject: Ticket".utf8))
        #expect(URLComponents(url: (await transport.requests[0]).url!, resolvingAgainstBaseURL: false)?.queryItems == [.init(name: "format", value: "raw")])
    }

    @Test func replyAndDestructiveMutationRequireConfirmationWithoutNetworkCall() async throws {
        let transport = EmailTransportSpy([]), provider = try GmailEmailProvider(accessToken: "token", transport: transport)
        await #expect(throws: GmailError.confirmationRequired) { try await provider.sendReply(.init(rawRFC2822: Data(), threadID: "t"), confirmed: false) }
        await #expect(throws: GmailError.confirmationRequired) { try await provider.mutate(messageID: "m", mutation: .trash, confirmed: false) }
        #expect(await transport.requests.isEmpty)
    }

    @Test func malformedOrFailedProviderResponseNeverBecomesSuccess() async throws {
        let transport = EmailTransportSpy([.init(status: 500, data: Data())])
        let provider = try GmailEmailProvider(accessToken: "token", transport: transport)
        await #expect(throws: GmailError.http(500)) { try await provider.search(query: "invoice", limit: 5) }
    }
}
