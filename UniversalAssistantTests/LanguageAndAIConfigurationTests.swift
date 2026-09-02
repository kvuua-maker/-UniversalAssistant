import Foundation
import Testing
@testable import UniversalAssistant

struct LanguageAndAIConfigurationTests {
    @Test func uiAndCommandLanguagesAreIndependentAndPersistent() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let persistence = LanguageConfigurationStore(store: LocalStore(baseDirectory: directory))
        let value = LanguageConfiguration(uiLanguage: .de, commandLanguage: .uk)
        try await persistence.save(value)
        #expect(try await persistence.load() == value)
        #expect(value.voiceLocale.identifier == "uk-UA")
    }

    @Test func allFiveLanguagesHaveExplicitVoiceLocalesAndAutomaticMode() {
        let expected: [CommandLanguage: String] = [.uk:"uk-UA", .ru:"ru-RU", .en:"en-US", .de:"de-DE", .fr:"fr-FR"]
        for (language, locale) in expected {
            #expect(LanguageConfiguration(uiLanguage: .uk, commandLanguage: language).voiceLocale.identifier == locale)
        }
        #expect(!LanguageConfiguration().voiceLocale.identifier.isEmpty)
    }

    @Test func optionalUserConnectedAIDefaultsOffAndStoresOnlySecretReference() {
        let disabled = UserConnectedAIConfiguration()
        #expect(!disabled.isEnabled)
        #expect(!disabled.isUsable)
        let enabled = UserConnectedAIConfiguration(isEnabled: true, provider: .openAI, credentialReference: "keychain://owner/openai")
        #expect(enabled.isUsable)
        #expect(!enabled.credentialReference!.contains("sk-"))
        for provider in UserAIProvider.allCases {
            #expect(UserConnectedAIConfiguration(isEnabled: true, provider: provider, credentialReference: "keychain://owner/ai").isUsable)
        }
    }

    @Test("Mixed language and natural word order", arguments: [
        ("Відкрий Telegram", CommandIntent.open),
        ("Telegram відкрий", CommandIntent.open),
        ("Покажи нову collection Baldinini", CommandIntent.fashionDiscovery),
        ("Мені кави хочеться", CommandIntent.placeSearch)
    ])
    func mixedNaturalCommands(_ phrase: String, _ expected: CommandIntent) {
        #expect(LocalCommandEngine().parse(phrase).intent == expected)
    }

    @Test("Colloquial, imperfect and inflected commands", arguments: [
        ("Будь ласка відкрий телеграмм", CommandIntent.open),
        ("Можеш нагадати мені завтра", CommandIntent.reminderCreate),
        ("Покажи колекції Baldinini", CommandIntent.fashionDiscovery)
    ])
    func tolerantCommandGrammar(_ phrase: String, _ expected: CommandIntent) {
        #expect(LocalCommandEngine().parse(phrase).intent == expected)
    }

    @Test func surroundingLanguageDoesNotCorruptBrandOrAppName() {
        let fashion = LocalCommandEngine().parse("Покажи new collection Baldinini")
        let app = LocalCommandEngine().parse("Будь ласка відкрий Telegram Business")
        #expect(fashion.constraints.brand == "Baldinini")
        #expect(app.entities["app"] == "Telegram Business")
    }
}
