import Testing
@testable import UniversalAssistant

@MainActor
struct AssistantResultStateTests {
    @Test func successfulCommandProducesCompactResult() {
        let model = AssistantViewModel()
        model.input = "Weather tomorrow"
        model.submit()

        guard case .completed(let summary) = model.resultState else {
            Issue.record("Expected a completed result")
            return
        }
        #expect(summary.request == "Weather tomorrow")
        #expect(summary.intent == .weather)
        #expect(summary.symbolName == "cloud.sun.fill")
    }

    @Test func unknownCommandRequestsClarificationTruthfully() {
        let model = AssistantViewModel()
        model.input = "невизначений запит"
        model.submit()

        guard case .clarification(let summary) = model.resultState else {
            Issue.record("Expected clarification")
            return
        }
        #expect(summary.intent == .unknown)
        #expect(summary.request == "невизначений запит")
    }
}
