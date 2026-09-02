import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Localization and accessibility QA")
struct LocalizationAccessibilityTests {
    private let locales = ["uk", "en", "de", "fr", "ru"]

    @Test func everyShippedLocaleHasTheSameNonemptyKeysAndFormatPlaceholders() throws {
        let tables = try Dictionary(uniqueKeysWithValues: locales.map { locale in
            (locale, try strings(locale))
        })
        let canonical = try #require(tables["uk"])
        for locale in locales {
            let table = try #require(tables[locale])
            #expect(Set(table.keys) == Set(canonical.keys))
            #expect(table.values.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            #expect(table["commerce_estimated_total_format"]?.contains("%@") == true)
        }
    }

    @Test func currencyFormattingRespondsToRuntimeRegionWithoutChangingStoredMoney() {
        let money = Money(amount: Decimal(string: "1234.50")!, currency: "EUR")
        let german = LocalizedFormatting.money(money, locale: Locale(identifier: "de_DE"))
        let english = LocalizedFormatting.money(money, locale: Locale(identifier: "en_US"))
        #expect(german != english)
        #expect(german.contains("1.234,50"))
        #expect(english.contains("1,234.50"))
        #expect(money.amount == Decimal(string: "1234.50")!)
    }

    @Test func longGermanFrenchAndCyrillicCriticalLabelsRemainAvailable() throws {
        for locale in ["de", "fr", "uk", "ru"] {
            let table = try strings(locale)
            for key in ["type_command", "microphone_denied", "commerce_buy_hint", "risk_consequential"] {
                #expect(table[key] != nil)
            }
        }
    }

    private func strings(_ locale: String) throws -> [String: String] {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("UniversalAssistant/Resources/\(locale).lproj/Localizable.strings")
        let content = try String(contentsOf: url, encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #""([^"]+)"\s*=\s*"([^"]*)";"#)
        return Dictionary(uniqueKeysWithValues: regex.matches(
            in: content, range: NSRange(content.startIndex..., in: content)
        ).compactMap { match in
            guard let keyRange = Range(match.range(at: 1), in: content),
                  let valueRange = Range(match.range(at: 2), in: content) else { return nil }
            return (String(content[keyRange]), String(content[valueRange]))
        })
    }
}
