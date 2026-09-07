import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Natural date and time resolution")
struct NaturalDateTimeResolverTests {
    private let resolver = NaturalDateTimeResolver()
    private let zone = TimeZone(identifier: "Europe/Kyiv")!
    private let reference = Date(timeIntervalSince1970: 1_725_192_000)

    @Test(arguments: [
        ("Завтра о 09:30", "uk_UA"),
        ("Завтра в 09:30", "ru_RU"),
        ("Tomorrow at 9:30 am", "en_US"),
        ("Morgen um 09:30", "de_DE"),
        ("Demain à 09:30", "fr_FR")
    ])
    func resolvesFiveLanguagesWithExplicitLocaleAndTimeZone(input: String, localeID: String) throws {
        let result = resolver.resolve(input, locale: Locale(identifier: localeID), timeZone: zone, relativeTo: reference)
        let resolved = try #require({
            if case let .resolved(value) = result { return value }
            return nil
        }())
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        #expect(calendar.dateComponents([.hour, .minute], from: resolved.instant).hour == 9)
        #expect(calendar.dateComponents([.hour, .minute], from: resolved.instant).minute == 30)
        #expect(resolved.timeZoneIdentifier == zone.identifier)
        #expect(resolved.precision == .minute)
    }

    @Test(arguments: [
        ("Створи завтра о п'ятнадцятій подію", "uk_UA", 15),
        ("Напомни завтра в двенадцать", "ru_RU", 12)
    ])
    func resolvesSpokenUkrainianAndRussianHours(input: String, localeID: String, expectedHour: Int) throws {
        let result = resolver.resolve(input, locale: Locale(identifier: localeID), timeZone: zone, relativeTo: reference)
        let resolved = try #require({
            if case let .resolved(value) = result { return value }
            return nil
        }())
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        #expect(calendar.component(.hour, from: resolved.instant) == expectedHour)
        #expect(calendar.component(.minute, from: resolved.instant) == 0)
    }

    @Test func eventKitArgumentsRemoveSpokenTimeWithoutDamagingTitle() throws {
        let command = LocalCommandEngine().parse("Створи завтра о п'ятнадцятій подію Тест UniversalAssistant")
        let values = EventKitCommandArgumentExtractor().extract(command, now: reference, timeZone: zone)
        #expect(values.subject == "Тест UniversalAssistant")
        #expect(values.dateTime != nil)
    }

    @Test func distinguishesRelativeDaysAndPreservesDayPrecision() throws {
        let today = try resolved("сьогодні")
        let tomorrow = try resolved("tomorrow")
        let afterTomorrow = try resolved("übermorgen")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        #expect(calendar.dateComponents([.day], from: today.instant, to: tomorrow.instant).day == 1)
        #expect(calendar.dateComponents([.day], from: today.instant, to: afterTomorrow.instant).day == 2)
        #expect(today.precision == .day)
    }

    @Test func ambiguityAndInvalidClockRemainUnresolvedOrDayOnly() throws {
        #expect(resolver.resolve("some day", locale: .init(identifier: "en"), timeZone: zone, relativeTo: reference) == .unresolved)
        let invalid = try resolved("tomorrow at 29:75")
        #expect(invalid.precision == .day)
    }

    @Test func resolvesRelativeMinutesAndCleansReminderPayload() throws {
        let result = resolver.resolve("Нагадай мені через 10 хвилин вимкнути духовку", locale: .init(identifier: "uk_UA"), timeZone: zone, relativeTo: reference)
        guard case let .resolved(value) = result else { Issue.record("Expected relative reminder time"); return }
        #expect(value.instant.timeIntervalSince(reference) == 600)
        #expect(value.precision == .minute)
        let command = LocalCommandEngine().parse("Нагадай мені через 10 хвилин вимкнути духовку")
        let args = EventKitCommandArgumentExtractor().extract(command, now: reference, timeZone: zone)
        #expect(args.subject == "вимкнути духовку")
    }

    @Test func cleansDayPeriodResidueFromReminderTitle() {
        let command = LocalCommandEngine().parse("Нагадай мені завтра о 9 ранку купити каву")
        let args = EventKitCommandArgumentExtractor().extract(command, now: reference, timeZone: zone)
        #expect(args.subject == "купити каву")
    }

    private func resolved(_ input: String) throws -> ResolvedNaturalDateTime {
        try #require({
            if case let .resolved(value) = resolver.resolve(
                input, locale: .init(identifier: "en"), timeZone: zone, relativeTo: reference
            ) { return value }
            return nil
        }())
    }
}
