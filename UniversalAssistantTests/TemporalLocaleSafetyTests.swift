import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Time, locale, currency and unit safety")
struct TemporalLocaleSafetyTests {
    @Test func absoluteInstantSurvivesRuntimeTimeZoneAndDSTChanges() throws {
        let instant = Date(timeIntervalSince1970: 1_773_000_000)
        let kyiv = try #require(TimeZone(identifier: "Europe/Kyiv"))
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        let stored = ZonedInstant(instant: instant, timeZone: kyiv)
        #expect(stored.instant == instant)
        #expect(stored.timeZone == kyiv)
        #expect(RuntimePresentationContext(locale: Locale(identifier: "uk_UA"), timeZone: berlin)
            .calendar().dateComponents([.hour], from: instant).hour != nil)
    }

    @Test func authoritativeExpiryToleratesOnlyDeclaredClockSkew() {
        let issued = Date(timeIntervalSince1970: 1_000)
        let window = AuthoritativeTimeWindow(issuedAt: issued, expiresAt: issued.addingTimeInterval(300), permittedClockSkew: 60)
        #expect(window.isValid(clientNow: issued.addingTimeInterval(-60)))
        #expect(window.isValid(clientNow: issued.addingTimeInterval(360)))
        #expect(!window.isValid(clientNow: issued.addingTimeInterval(361)))
    }

    @Test func differentCurrenciesAreNeverComparedAsRawNumbers() {
        #expect(Money(amount: 1, currency: "EUR").safelyCompare(to: .init(amount: 100, currency: "UAH")) ==
                .currencyConversionRequired(left: "EUR", right: "UAH"))
        #expect(Money(amount: 1, currency: "EUR").safelyCompare(to: .init(amount: 2, currency: "EUR")) ==
                .ordered(.orderedAscending))
    }

    @Test func normalizedCompatibleUnitsCompareAndIncompatibleUnitsDoNot() throws {
        let kilo = try GroceryQuantity.normalized(amount: 1, token: "kg")
        let grams = try GroceryQuantity.normalized(amount: 1_000, token: "g")
        let liter = try GroceryQuantity.normalized(amount: 1, token: "l")
        #expect(kilo.safelyCompare(to: grams) == .ordered(.orderedSame))
        #expect(kilo.safelyCompare(to: liter) == .incompatibleUnits(left: .gram, right: .milliliter))
    }

    @Test func storedIntentIsLocaleNeutralWhilePresentationChangesAtRuntime() {
        let command = LocalCommandEngine().parse("Знайди взуття до 1200 грн")
        let encoded = try! JSONEncoder().encode(command)
        let decoded = try! JSONDecoder().decode(StructuredCommand.self, from: encoded)
        #expect(decoded == command)
        #expect(LocalizedFormatting.money(.init(amount: 1200, currency: "UAH"), locale: .init(identifier: "uk_UA")) !=
                LocalizedFormatting.money(.init(amount: 1200, currency: "UAH"), locale: .init(identifier: "de_DE")))
    }
}
