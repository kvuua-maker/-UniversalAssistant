import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Canonical reference scenarios MS-499–520")
struct CanonicalReferenceScenarioTests {
    private let parser = LocalCommandEngine()

    @Test("Exact canonical command routes", arguments: [
        ("Хочу кави", CommandIntent.placeSearch), ("Знайди аптеку по дорозі додому", .routeAwareSearch),
        ("Запиши завтра стоматолога о 10", .calendarCreate), ("Перенеси стоматолога на п’ятницю о 15", .calendarUpdate),
        ("Скасуй завтра стоматолога", .calendarDelete), ("Відміни останнє", .undo), ("Подзвони мамі", .contactCall),
        ("Напиши Олегу, що буду через 20 хвилин", .messageCompose), ("Веди додому", .navigation),
        ("Покажи нову колекцію Baldinini", .fashionDiscovery), ("Знайди Baldinini 43 розміру", .productSearch),
        ("Порахуй кошик у Сільпо, АТБ, Форі та Fozzy", .groceryBasket), ("Розділи кошик максимум між двома магазинами", .groceryBasket),
        ("Найдешевше таксі додому", .taxiCompare), ("Таксі додому, чекати максимум 5 хвилин", .taxiSearch),
        ("Потрібен евакуатор", .serviceSearch), ("Мені завтра треба бути у Львові до 14", .travelPlan),
        ("Подзвони 112", .emergency), ("Увімкни диктофон", .audioRecord), ("Відкрий другий", .open),
        ("Покажи маршрут", .routeSearch), ("Запиши стоматолога і купи Sensodyne по дорозі та порахуй виїзд", .multiStep)
    ])
    func route(_ phrase: String, _ expected: CommandIntent) {
        let command = parser.parse(phrase)
        #expect(command.intent == expected)
        #expect(!command.needsClarification)
    }

    @Test func consequentialAndContextSemanticsRemainTyped() {
        #expect(parser.parse("Подзвони 112").risk == .emergency)
        #expect(parser.parse("Запиши завтра стоматолога о 10").risk == .reversible)
        let taxi = parser.parse("Таксі додому, чекати максимум 5 хвилин")
        #expect(taxi.constraints.maximumWaitMinutes == 5)
        #expect(taxi.constraints.hardConstraintKeys.contains("maximumWaitMinutes"))
        let openSecond = parser.parse("Відкрий другий")
        #expect(openSecond.constraints.ordinal == 2)
        var context = CurrentContext(); let now = Date(timeIntervalSince1970: 1_000)
        context.store(results: ["first", "second"], now: now, lifetime: 30)
        #expect(context.resolve(openSecond, now: now) == "second")
    }
}
