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

    @Test func unavailableNotesDatabaseTerminatesTruthfullyWithoutWrongFilesPresentation() async throws {
        let model = AssistantViewModel(compactResultDuration: .milliseconds(200))
        model.input = "Покажи нотатки"
        model.submit()
        try await waitUntil { if case .failure = model.resultState { true } else { false } }
        guard case .failure = model.resultState else {
            Issue.record("Expected the truthful Notes database limitation")
            return
        }
        #expect(model.capabilityPresentation == nil)
        #expect(model.statusText != AppText.value("processing"))
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

    @Test func novelInformationalWordingUsesTypedWebHandoffInsteadOfAcknowledgement() async throws {
        let model = AssistantViewModel()
        model.input = "Чому небо змінює колір перед заходом сонця?"
        model.submit()
        try await waitUntil { if case .webHandoff = model.resultState { return true }; return false }
        guard case .webHandoff(let result) = model.resultState else {
            Issue.record("Expected a typed web handoff")
            return
        }
        #expect(result.destination.host == "www.google.com")
        #expect(result.query.contains("небо"))
    }

    @Test func russianNovelInformationalWordingUsesSameMechanism() async throws {
        let model = AssistantViewModel()
        model.input = "Почему листья меняют цвет осенью?"
        model.submit()
        try await waitUntil { if case .webHandoff = model.resultState { return true }; return false }
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

    @Test func sharedURLRemainsTypedURLAndIsNeverConvertedToSearchText() {
        let model = AssistantViewModel()
        model.ingestShared(.init(kind: "url", value: "https://www.apple.com/iphone", receivedAt: .now))
        guard case let .webHandoff(result) = model.resultState else { Issue.record("Expected exact shared URL handoff"); return }
        #expect(result.destination.absoluteString == "https://www.apple.com/iphone")
        #expect(result.destination.host == "www.apple.com")
        #expect(result.kind == .system)
        model.input = "Відкрий це"
        model.submit()
        guard case let .webHandoff(followUp) = model.resultState else { Issue.record("Expected contextual URL handoff"); return }
        #expect(followUp.destination.absoluteString == "https://www.apple.com/iphone")
    }

    private func waitUntil(_ condition:   () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for ViewModel state")
    }
}
