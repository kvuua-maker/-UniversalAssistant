import Foundation

enum AppText {
    /// UI language selected in Settings. `String(localized:)` resolves against
    /// the process locale, not the SwiftUI environment, so the choice has to be
    /// passed explicitly or a language picker would be cosmetic.
    nonisolated(unsafe) private static var storedLanguageIdentifier = "uk"
    private static let lock = NSLock()

    static var languageIdentifier: String {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedLanguageIdentifier
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storedLanguageIdentifier = newValue
        }
    }

    static func value(_ key: String.LocalizationValue) -> String {
        String(localized: key, locale: Locale(identifier: languageIdentifier))
    }

    static func feedback(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: "Feedback", locale: Locale(identifier: languageIdentifier))
    }
}
