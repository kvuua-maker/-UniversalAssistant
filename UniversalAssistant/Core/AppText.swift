import Foundation

enum AppText {
    static func value(_ key: String.LocalizationValue) -> String { String(localized: key) }
    static func feedback(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: "Feedback")
    }
}
