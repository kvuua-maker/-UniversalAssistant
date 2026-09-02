import Foundation

enum UILanguage: String, Codable, CaseIterable, Sendable { case uk, ru, en, de, fr }

struct LanguageConfiguration: Equatable, Codable, Sendable {
    var uiLanguage: UILanguage
    var commandLanguage: CommandLanguage

    init(uiLanguage: UILanguage = .uk, commandLanguage: CommandLanguage = .automatic) {
        self.uiLanguage = uiLanguage
        self.commandLanguage = commandLanguage
    }

    var voiceLocale: Locale {
        let identifier = switch commandLanguage {
        case .uk: "uk-UA"; case .ru: "ru-RU"; case .en: "en-US"
        case .de: "de-DE"; case .fr: "fr-FR"
        case .automatic: Locale.current.identifier
        }
        return Locale(identifier: identifier)
    }
}

actor LanguageConfigurationStore {
    private let store: LocalStore
    init(store: LocalStore = .shared) { self.store = store }
    func load() async throws -> LanguageConfiguration {
        try await store.load(LanguageConfiguration.self, from: "language-configuration.json") ?? .init()
    }
    func save(_ configuration: LanguageConfiguration) async throws {
        try await store.save(configuration, as: "language-configuration.json")
    }
}

enum UserAIProvider: String, Codable, CaseIterable, Sendable { case openAI, anthropic, gemini, compatible }

struct UserConnectedAIConfiguration: Equatable, Codable, Sendable {
    var isEnabled = false
    var provider: UserAIProvider?
    /// Reference to a Keychain/server-side secret, never the secret itself.
    var credentialReference: String?

    var isUsable: Bool {
        isEnabled && provider != nil && credentialReference?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}
