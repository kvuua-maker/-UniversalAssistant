import Foundation
import Testing
@testable import UniversalAssistant

struct LocalCommandEngineTests {
    private let engine = LocalCommandEngine()

    @Test("Open intent and language", arguments: [
        ("Відкрий Telegram", CommandLanguage.uk), ("Открой Telegram", .ru), ("Open Telegram", .en), ("Öffne Telegram", .de), ("Ouvre Telegram", .fr)
    ])
    func parsesOpen(_ phrase: String, _ language: CommandLanguage) {
        let command = engine.parse(phrase)
        #expect(command.intent == .open); #expect(command.language == language); #expect(command.entities["app"] == "Telegram")
    }

    @Test func extractsHardCommerceConstraints() {
        let command = engine.parse("Знайди Baldinini 43 розміру до 12000 грн")
        #expect(command.intent == .productSearch); #expect(command.constraints.size == "43")
        #expect(command.constraints.maximumPrice == 12000); #expect(command.constraints.currency == "UAH")
        #expect(command.constraints.hardConstraintKeys == ["size", "maximumPrice"])
    }

    @Test("Representative deterministic intents", arguments: [
        ("Нагадай завтра о 9", CommandIntent.reminderCreate), ("Позвони маме", .contactCall), ("Weather tomorrow", .weather),
        ("Zeige neue Kollektion", .fashionDiscovery), ("Billet pour Paris", .ticketSearch), ("Подзвони 112", .emergency)
    ])
    func intentCorpus(_ phrase: String, _ intent: CommandIntent) { #expect(engine.parse(phrase).intent == intent) }

    @Test func contextResolvesAndExpires() {
        let now = Date(timeIntervalSince1970: 1_000); var context = CurrentContext()
        context.store(results: ["A", "B", "C"], now: now, lifetime: 30)
        #expect(context.resolve(engine.parse("другий"), now: now) == "B")
        #expect(context.resolve(engine.parse("другий"), now: now.addingTimeInterval(31)) == nil)
    }

    @Test func unknownIsTruthful() {
        let command = engine.parse("невизначений запит")
        #expect(command.intent == .unknown); #expect(command.needsClarification)
    }
}
