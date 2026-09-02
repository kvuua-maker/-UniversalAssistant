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
        let model = AssistantViewModel(compactResultDuration: .milliseconds(200))
        model.input = "Weather tomorrow"
        model.submit()
        try await Task.sleep(for: .milliseconds(100))
        model.input = "Покажи погоду"
        model.submit()
        try await Task.sleep(for: .milliseconds(150))
        guard case .recognized(let summary) = model.resultState else {
            Issue.record("Old timer must not dismiss the newer confirmation")
            return
        }
        #expect(summary.intent == .weather)
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.resultState == .idle)
    }

    @Test func leavingActiveSceneStopsTransientListeningState() {
        let model = AssistantViewModel()
        model.isListening = true
        model.handleSceneBecameInactive()
        #expect(!model.isListening)
    }

    @Test func perceptibleProcessingActionFailureAndExpandedResultsAreTyped() {
        let model = AssistantViewModel()
        model.beginProcessing()
        #expect(model.resultState == .processing)
        model.requireAction(prompt: "Оберіть один варіант", choices: ["A", "B"])
        #expect(model.resultState == .actionRequired(.init(prompt: "Оберіть один варіант", choices: ["A", "B"])))
        model.presentFailure(message: "Сервіс недоступний", recoveryAction: "Спробувати пізніше")
        #expect(model.resultState == .failure(.init(message: "Сервіс недоступний", recoveryAction: "Спробувати пізніше")))
        let summary = ResultSummary(request: "Trip options", intent: .travelPlan, risk: .informational)
        model.presentExpanded(summary)
        #expect(model.resultState == .expanded(summary))
    }
}
