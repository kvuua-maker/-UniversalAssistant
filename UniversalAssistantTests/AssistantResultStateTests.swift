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

    @Test func compactConfirmationDismissesAndNewSubmissionCancelsOldTimer() async throws {
        let model = AssistantViewModel(compactResultDuration: .milliseconds(20))
        model.input = "Weather tomorrow"
        model.submit()
        try await Task.sleep(for: .milliseconds(10))
        model.input = "Покажи погоду"
        model.submit()
        try await Task.sleep(for: .milliseconds(15))
        guard case .recognized(let summary) = model.resultState else {
            Issue.record("Old timer must not dismiss the newer confirmation")
            return
        }
        #expect(summary.intent == .weather)
        try await Task.sleep(for: .milliseconds(15))
        #expect(model.resultState == .idle)
    }
}
