import Foundation
import Testing
@testable import UniversalAssistant

@MainActor
struct AssistantResultStateTests {
    @Test func parserOnlyCommandDoesNotMasqueradeAsSuccessfulExecution() async throws {
        let model = AssistantViewModel()
        model.input = "Створи нотатку"
        model.submit()
        try await waitUntil { if case .clarification = model.resultState { true } else { false } }
        guard case .clarification = model.resultState else {
            Issue.record("A note without content must request the missing content")
            return
        }
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

    @Test func newerParserOnlySubmissionRemainsTruthfullyUnavailable() async throws {
        let model = AssistantViewModel(compactResultDuration: .milliseconds(200))
        model.input = "Покажи нотатки"
        model.submit()
        try await waitUntil { model.capabilityPresentation == .documents }
        guard case .recognized = model.resultState,
              case .documents? = model.capabilityPresentation else {
            Issue.record("Expected the typed system document presentation")
            return
        }
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

    private func waitUntil(_ condition:   () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for ViewModel state")
    }
}
