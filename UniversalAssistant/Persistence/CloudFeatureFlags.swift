import Foundation

/// CloudKit is opt-in per build. Constructing `CKContainer` when the App ID,
/// entitlements and provisioned container disagree raises an Objective-C
/// exception that Swift cannot catch, which surfaces as SIGTRAP on launch.
/// Every CloudKit entry point must consult this flag before touching a
/// container so the app degrades to local-only instead of crashing.
enum CloudFeatureFlags {
    static var cloudSyncEnabled: Bool {
        let value = Bundle.main.object(forInfoDictionaryKey: "UAUseCloudKitSync")
        if let flag = value as? Bool { return flag }
        if let text = value as? String {
            return ["YES", "TRUE", "1"].contains(text.uppercased())
        }
        return false
    }
}
