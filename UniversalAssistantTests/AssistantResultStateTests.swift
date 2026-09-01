import Testing
@testable import UniversalAssistant

@MainActor
struct AssistantResultStateTests {
    @Test func successfulCommandProducesCompactResult() {
        let model = AssistantViewModel()
        model.input = "Weather tomorrow"
        model.submit()

        guard case .recognized(let summary) = model.resultState else {
            Issue.record("Expected a recognized result")
            return
        }
        #expect(summary.request == "Weather tomorrow")
        #expect(summary.intent == .weather)
        #expect(summary.symbolName == "cloud.sun.fill")
        #expect(model.interactionDecision?.pattern == .compactAcknowledgement)
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
