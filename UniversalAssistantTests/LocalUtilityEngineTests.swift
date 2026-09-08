import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Deterministic local utility execution")
@MainActor
struct LocalUtilityEngineTests {
    let engine = LocalUtilityEngine()
    let locale = Locale(identifier: "uk_UA")
    let utc = TimeZone(secondsFromGMT: 0)!

    @Test("Arithmetic", arguments: [
        ("Скільки буде 125 помножити на 8?", "1 000"),
        ("Сколько будет 20 разделить на 4?", "5"),
        ("Додай -2,5 плюс 4", "1,5"),
        ("Відняти 7 мінус 10", "-3")
    ]) func arithmetic(phrase: String, expected: String) throws {
        #expect(try engine.execute(phrase, locale: locale, timeZone: utc, now: .now) == expected)
    }

    @Test("Percent operations", arguments: [
        ("Скільки буде 15 відсотків від 2400?", "360"),
        ("Збільш 200 на 10 відсотків", "220"),
        ("Зменш 200 на 10 відсотків", "180")
    ]) func percentages(phrase: String, expected: String) throws {
        #expect(try engine.execute(phrase, locale: locale, timeZone: utc, now: .now) == expected)
    }

    @Test func fixedUnitConversionsRespectDirectionAndDecimals() throws {
        #expect(try engine.execute("Скільки буде 10 кілометрів у милях?", locale: locale, timeZone: utc, now: .now) == "6,213712 mi")
        #expect(try engine.execute("2,5 miles у кілометрах", locale: locale, timeZone: utc, now: .now) == "4,02336 km")
        #expect(try engine.execute("0 градусів Celsius у Fahrenheit", locale: locale, timeZone: utc, now: .now) == "32 °F")
    }

    @Test func dateDayAndTimeUseSuppliedTimezone() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = utc
        let date = try #require(calendar.date(from: .init(year: 2024, month: 9, day: 2, hour: 14, minute: 55)))
        #expect(try engine.execute("Який сьогодні день тижня?", locale: locale, timeZone: utc, now: date).lowercased().contains("понеділ"))
        #expect(try engine.execute("Яка сьогодні дата?", locale: locale, timeZone: utc, now: date).contains("2"))
        #expect(try engine.execute("Котра година?", locale: locale, timeZone: utc, now: date) == "14:55")
    }

    @Test func structuredSpeechNumberGroupsAndNaturalClockVariantsStayLocal() throws {
        #expect(try engine.execute("Скільки буде 15 відсотків від 2000 400?", locale: locale, timeZone: utc, now: .now) == "360")
        #expect(try engine.execute("Скільки буде 15 відсотків від 2 400?", locale: locale, timeZone: utc, now: .now) == "360")
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = utc
        let date = try #require(calendar.date(from: .init(year: 2026, month: 9, day: 8, hour: 6, minute: 7)))
        #expect(try engine.execute("Яке сьогодні число?", locale: locale, timeZone: utc, now: date).contains("8"))
        #expect(try engine.execute("Скільки зараз часу?", locale: locale, timeZone: utc, now: date) == "06:07")
        #expect(LocalCommandEngine().parse("Яке сьогодні число?").intent == .localUtility)
        #expect(LocalCommandEngine().parse("Сколько сейчас времени?").intent == .localUtility)
    }

    @Test func currencyIsRecognizedSeparatelyAndNeverComputedAsAUnit() {
        #expect(LocalCommandEngine().parse("Переведи 150 доларів у гривні").intent == .currencyConversion)
        #expect(LocalCommandEngine().parse("Покажи курс долара до гривні").intent == .currencyConversion)
    }

    @Test func naturalHomeInputReturnsInAppResultWithoutWebHandoff() async throws {
        let model = AssistantViewModel()
        model.input = "Скільки буде 347 помножити на 28?"
        model.submit()
        try await waitUntil { if case .deterministic = model.resultState { true } else { false } }
        guard case let .deterministic(result) = model.resultState else { return }
        #expect(result.primaryAnswer == "9 716")
        #expect(!result.primaryAnswer.contains("localUtility"))
    }

    @Test func currencyWithoutConfiguredRateUsesTruthfulProviderFallback() async throws {
        let executor = ProductionCanonicalCapabilityExecutor(personalSearchSources: [])
        let command = LocalCommandEngine().parse("Переведи 150 доларів у гривні")
        await #expect(throws: CanonicalCapabilityExecutionError.externalProviderRequired("current_fx_rate_for_currency")) { try await executor.execute(command) }
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<100 { if condition() { return }; try await Task.sleep(for: .milliseconds(10)) }
        Issue.record("Timed out waiting for local utility result")
    }
}
