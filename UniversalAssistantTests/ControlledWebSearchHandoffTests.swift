import Testing
@testable import UniversalAssistant

struct ControlledWebSearchHandoffTests {
    private let parser = LocalCommandEngine()
    private let handoff = ControlledWebSearchHandoff()

    @Test func buildsEncodedHTTPSDestinationOnlyWhenStructuredCapabilityIsUnavailable() throws {
        let command = parser.parse("Пошукай в інтернеті Swift actors & cancellation")
        let url = try handoff.destination(for: command, structuredCapabilityAvailable: false)
        #expect(url.scheme == "https")
        #expect(url.host == "www.google.com")
        #expect(url.query?.contains("q=Swift%20actors%20%26%20cancellation") == true)
        #expect(throws: WebSearchHandoffError.structuredCapabilityAvailable) {
            try handoff.destination(for: command, structuredCapabilityAvailable: true)
        }
    }

    @Test func rejectsEmptyAndNonWebCommands() {
        #expect(throws: WebSearchHandoffError.emptyQuery) {
            try handoff.destination(for: parser.parse("Пошукай в інтернеті"), structuredCapabilityAvailable: false)
        }
        #expect(throws: WebSearchHandoffError.structuredCapabilityAvailable) {
            try handoff.destination(for: parser.parse("Покажи погоду"), structuredCapabilityAvailable: false)
        }
    }
}
