import Testing
@testable import UniversalAssistant

struct LocalCommandEngineTests {
    private let engine = LocalCommandEngine()

    @Test("Open intent across launch languages", arguments: ["Відкрий Telegram", "Открой Telegram", "Open Telegram", "Öffne Telegram", "Ouvre Telegram"])
    func parsesOpen(_ phrase: String) { #expect(engine.parse(phrase).intent == .open) }

    @Test func trimsAndPreservesOriginal() {
        let command = engine.parse("  Відкрий Укрзалізницю  ")
        #expect(command.originalText == "  Відкрий Укрзалізницю  ")
        #expect(command.normalizedText == "відкрий укрзалізницю")
    }

    @Test func unknownIsTruthful() { #expect(engine.parse("невизначений запит").intent == .unknown) }
}
