import Foundation
import Testing
@testable import UniversalAssistant

@MainActor
struct AssistantResultStateTests {
    @Test func successfulCommandProducesCompactResult() {
        let model = AssistantViewModel()
        model.input = "Створи нотатку"
        model.submit()

        guard case .recognized(let summary) = model.resultState else {
            Issue.record("Expected a recognized result")
            return
        }
        #expect(summary.request == "Створи нотатку")
        #expect(summary.intent == .noteCreate)
        #expect(summary.symbolName == "sparkles")
        #expect(model.interactionDecision?.pattern == .directAction)
    }

    @Test func unknownCommandRequestsClarificationTruthfully() {
        let model = AssistantViewModel()
        model.input = "Щось цікаве"
        model.submit()

        guard case .clarification(let summary) = model.resultState else {
            Issue.record("Expected clarification")
            return
        }
        #expect(summary.intent == .unknown)
        #expect(summary.request == "Щось цікаве")
    }

    @Test func compactConfirmationDismissesAndNewSubmissionCancelsOldTimer() async throws {
        let model = AssistantViewModel(compactResultDuration: .milliseconds(200))
        model.input = "Створи нотатку"
        model.submit()
        try await Task.sleep(for: .milliseconds(100))
        model.input = "Покажи нотатки"
        model.submit()
        try await Task.sleep(for: .milliseconds(150))
        guard case .recognized(let summary) = model.resultState else {
            Issue.record("Old timer must not dismiss the newer confirmation")
            return
        }
        #expect(summary.intent == .noteQuery)
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

    @Test func novelInformationalWordingUsesTypedWebHandoffInsteadOfAcknowledgement() {
        let model = AssistantViewModel()
        model.input = "Чому небо змінює колір перед заходом сонця?"
        model.submit()
        guard case .webHandoff(let result) = model.resultState else {
            Issue.record("Expected a typed web handoff")
            return
        }
        #expect(result.destination.host == "www.google.com")
        #expect(result.query.contains("небо"))
    }

    @Test func russianNovelInformationalWordingUsesSameMechanism() {
        let model = AssistantViewModel()
        model.input = "Почему листья меняют цвет осенью?"
        model.submit()
        guard case .webHandoff(let result) = model.resultState else {
            Issue.record("Expected the same typed web handoff")
            return
        }
        #expect(result.destination.host == "www.google.com")
    }

    @Test func genuinelyAmbiguousUnknownStillClarifies() {
        let model = AssistantViewModel()
        model.input = "Щось цікаве"
        model.submit()
        guard case .clarification = model.resultState else {
            Issue.record("Expected bounded clarification")
            return
        }
    }
}
