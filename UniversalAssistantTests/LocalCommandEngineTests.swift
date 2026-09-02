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
        #expect(command.constraints.hardConstraintKeys == ["size", "maximumPrice", "brand"])
    }

    @Test("Representative deterministic intents", arguments: [
        ("Нагадай завтра о 9", CommandIntent.reminderCreate), ("Позвони маме", .contactCall), ("Weather tomorrow", .weather),
        ("Покажи погоду", .weather),
        ("Zeige neue Kollektion", .fashionDiscovery), ("Billet pour Paris", .ticketSearch), ("Подзвони 112", .emergency)
    ])
    func intentCorpus(_ phrase: String, _ intent: CommandIntent) { #expect(engine.parse(phrase).intent == intent) }

    @Test("Canonical intent recognition matrix", arguments: [
        ("Ресторан поруч", CommandIntent.restaurantSearch), ("Забронюй столик", .reservation),
        ("Виклич таксі", .taxiSearch), ("Побудуй маршрут", .routeSearch), ("Кав'ярня по дорозі", .routeAwareSearch),
        ("Що в календарі", .calendarQuery), ("Перенеси зустріч", .calendarUpdate), ("Видали зустріч", .calendarDelete),
        ("Покажи нагадування", .reminderQuery), ("Створи нотатку", .noteCreate), ("Покажи нотатки", .noteQuery),
        ("Список покупок", .shoppingList), ("Знайди контакт Ірина", .contactLookup),
        ("Громадський транспорт", .publicTransport), ("Як доїхати до вокзалу", .transportRoute),
        ("Купи квиток до Львова", .ticketPurchaseHandoff)
    ])
    func canonicalIntentRecognition(_ phrase: String, _ intent: CommandIntent) {
        let command = engine.parse(phrase)
        #expect(command.intent == intent)
        #expect(!command.needsClarification)
    }

    @Test("Remaining canonical intent recognition", arguments: [
        ("Готель у Львові", CommandIntent.hotelSearch), ("Сплануй подорож", .travelPlan),
        ("Виклич швидку", .emergency), ("Пошукай в інтернеті", .webSearch),
        ("Увімкни ліхтарик", .deviceAction), ("Дія в застосунку", .appAction),
        ("Запиши аудіо", .audioRecord), ("Покажи результат", .show),
        ("Відкрий Telegram", .open), ("Скасуй дію", .cancel),
        ("Відміни останнє", .undo), ("Коли я кажу ранок", .multiStep),
        ("Налаштування", .settings), ("Допомога", .help)
    ])
    func remainingCanonicalIntentRecognition(_ phrase: String, _ intent: CommandIntent) {
        #expect(engine.parse(phrase).intent == intent)
    }

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
