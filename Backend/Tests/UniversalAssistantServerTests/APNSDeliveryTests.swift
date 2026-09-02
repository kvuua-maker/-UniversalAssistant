import Foundation
import Testing
@testable import UniversalAssistantServer

private actor APNSTransportFixture: APNSTransport {
    let response: APNSHTTPResponse
    private(set) var request: APNSRequest?
    init(_ response: APNSHTTPResponse) { self.response = response }
    func send(_ request: APNSRequest) -> APNSHTTPResponse { self.request = request; return response }
}

private func registration(_ environment: APNSEnvironment = .sandbox) -> APNSDeviceRegistration {
    let now = Date()
    return .init(userID: "u", deviceID: "d", token: Data(repeating: 1, count: 32),
                 environment: environment, registeredAt: now, updatedAt: now)
}

@Suite("APNs delivery contract") struct APNSDeliveryTests {
    @Test func buildsExactSandboxRequestAndClassifiesSuccess() async throws {
        let transport = APNSTransportFixture(.init(statusCode: 200, apnsID: "id"))
        let client = APNSDeliveryClient(topic: "com.universalassistant.app", authorization: "bearer signed-jwt", transport: transport)
        let result = try await client.deliver(payload: .init(aps: .init(alert: "Traffic changed", threadID: "traffic"),
                                                              route: "universalassistant://open/task/1"),
                                              registration: registration(), collapseID: "traffic:1",
                                              expiresAt: Date().addingTimeInterval(300))
        #expect(result == .accepted(apnsID: "id"))
        let request = try #require(await transport.request)
        #expect(request.url.host == "api.sandbox.push.apple.com")
        #expect(request.headers["apns-collapse-id"] == "traffic:1")
    }

    @Test(arguments: [(410, "Unregistered"), (400, "BadDeviceToken")])
    func invalidTokensAreExplicitlyClassified(status: Int, reason: String) async throws {
        let transport = APNSTransportFixture(.init(statusCode: status, reason: reason))
        let client = APNSDeliveryClient(topic: "topic", authorization: "bearer signed-jwt", transport: transport)
        let outcome = try await client.deliver(payload: .init(aps: .init(alert: "Alert", threadID: "t"),
                                                               route: "universalassistant://open/task/1"),
                                               registration: registration(), collapseID: "c",
                                               expiresAt: Date().addingTimeInterval(60))
        #expect(outcome == .invalidToken)
    }

    @Test func rateLimitAndServerErrorsAreRetryableButBadRequestIsNot() async throws {
        for status in [429, 500] {
            let transport = APNSTransportFixture(.init(statusCode: status))
            let client = APNSDeliveryClient(topic: "topic", authorization: "bearer signed-jwt", transport: transport)
            let outcome = try await client.deliver(payload: .init(aps: .init(alert: "A", threadID: "t"), route: "universalassistant://open/task/1"), registration: registration(), collapseID: "c", expiresAt: Date().addingTimeInterval(60))
            #expect(outcome == .retryable(statusCode: status))
        }
    }

    @Test func missingCredentialStopsBeforeTransport() async throws {
        let transport = APNSTransportFixture(.init(statusCode: 200))
        let client = APNSDeliveryClient(topic: "topic", authorization: nil, transport: transport)
        await #expect(throws: APNSDeliveryError.missingAuthorization) {
            try await client.deliver(payload: .init(aps: .init(alert: "A", threadID: "t"), route: "universalassistant://open/task/1"), registration: registration(), collapseID: "c", expiresAt: Date().addingTimeInterval(60))
        }
        #expect(await transport.request == nil)
    }
}
