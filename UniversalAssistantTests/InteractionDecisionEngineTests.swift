import Testing
@testable import UniversalAssistant

struct InteractionDecisionEngineTests {
    private let parser = LocalCommandEngine()
    private let engine = InteractionDecisionEngine()

    @Test func ambiguityRequiresOneClarificationPattern() {
        #expect(engine.decide(for: parser.parse("невизначений запит")).pattern == .clarify)
    }

    @Test func clearOpenUsesDirectPattern() {
        #expect(engine.decide(for: parser.parse("Відкрий Telegram")).pattern == .directAction)
    }

    @Test func productSearchUsesVisualSelectionPattern() {
        #expect(engine.decide(for: parser.parse("Знайди Baldinini 43 розміру")).pattern == .fullScreenResult)
    }

    @Test func emergencyRequiresSafetyConfirmation() {
        #expect(engine.decide(for: parser.parse("Подзвони 112")).pattern == .confirmation)
    }

    @Test func deleteNeverSilentlyClaimsCompletion() {
        let command = StructuredCommand(
            originalText: "Скасуй подію",
            normalizedText: "скасуй подію",
            language: .uk,
            intent: .calendarDelete,
            risk: .reversible
        )
        #expect(engine.decide(for: command).pattern == .confirmation)
    }
}
