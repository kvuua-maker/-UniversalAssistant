import Foundation

enum AppText {
    static func value(_ key: String.LocalizationValue) -> String { String(localized: key) }
}
