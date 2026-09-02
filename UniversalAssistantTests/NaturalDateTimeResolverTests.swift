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

    private func resolved(_ input: String) throws -> ResolvedNaturalDateTime {
        try #require({
            if case let .resolved(value) = resolver.resolve(
                input, locale: .init(identifier: "en"), timeZone: zone, relativeTo: reference
            ) { return value }
            return nil
        }())
    }
}
