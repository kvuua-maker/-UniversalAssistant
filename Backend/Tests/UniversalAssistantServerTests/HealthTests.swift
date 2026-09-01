import Testing
@testable import UniversalAssistantServer

@Test func healthContractIsStable() throws {
    let response = HealthResponse()
    #expect(response.status == .healthy)
    #expect(response.version == "v1")
}
