import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Deterministic verified result composition")
struct DeterministicResultComposerTests {
    @Test func verifiedFactsComposeInStablePriorityOrderWithZeroAI() throws {
        let now = Date.now
        let result = try DeterministicResultComposer().compose(primaryAnswer: "Варіант A відповідає умовам", facts: [
            .init(id: "price", label: "Ціна", value: "120 EUR", state: .verified, source: "provider", observedAt: now, priority: 5),
            .init(id: "weather", label: "Погода", value: "24 °C", state: .verified, source: "WeatherKit", observedAt: now, priority: 10)
        ])
        #expect(result.aiInvocationCount == 0)
        #expect(result.facts.map(\.id) == ["weather", "price"])
    }

    @Test func unknownFactCannotCarryInventedValue() {
        let fact = ResultFact(id: "hotel", label: "Готель", value: "99 EUR", state: .unknown, source: nil, observedAt: nil, priority: 1)
        #expect(throws: ResultComposerError.unverifiedValue) { try DeterministicResultComposer().compose(primaryAnswer: "Частковий результат", facts: [fact]) }
    }

    @Test func unavailableFactRemainsExplicitAndValid() throws {
        let fact = ResultFact(id: "hotel", label: "Готель", value: nil, state: .unavailable, source: nil, observedAt: nil, priority: 1)
        let result = try DeterministicResultComposer().compose(primaryAnswer: "Доступний маршрут", facts: [fact], warnings: ["hotel_unavailable"])
        #expect(result.facts.count == 1)
        #expect(result.facts.first?.state == .unavailable)
    }
}
