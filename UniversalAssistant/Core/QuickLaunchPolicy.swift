import Foundation

enum QuickLaunchMechanism: String, Codable, CaseIterable, Sendable {
    case actionButton, backTap, appShortcut, homeScreenShortcut, assistiveTouch
}
enum SystemCapabilityAvailability: String, Codable, Sendable { case available, unavailable }
struct QuickLaunchCapabilities: Equatable, Codable, Sendable {
    let actionButton: SystemCapabilityAvailability
    let backTap: SystemCapabilityAvailability
    let appShortcut: SystemCapabilityAvailability
    let homeScreenShortcut: SystemCapabilityAvailability
    let assistiveTouch: SystemCapabilityAvailability
}
enum VoiceLaunchAvailability: Equatable, Sendable { case permitted, permissionRequired, unavailable }
enum QuickLaunchDestination: Equatable, Sendable { case listening, permissionFlow, textInput }

struct QuickLaunchPolicy: Sendable {
    func recommendedMechanisms(_ value: QuickLaunchCapabilities) -> [QuickLaunchMechanism] {
        let order: [QuickLaunchMechanism] = value.actionButton == .available
            ? [.actionButton, .backTap, .appShortcut, .homeScreenShortcut, .assistiveTouch]
            : [.backTap, .appShortcut, .homeScreenShortcut, .assistiveTouch]
        return order.filter { mechanism in
            switch mechanism {
            case .actionButton: value.actionButton == .available
            case .backTap: value.backTap == .available
            case .appShortcut: value.appShortcut == .available
            case .homeScreenShortcut: value.homeScreenShortcut == .available
            case .assistiveTouch: value.assistiveTouch == .available
            }
        }
    }

    func destination(voice: VoiceLaunchAvailability) -> QuickLaunchDestination {
        switch voice { case .permitted: .listening; case .permissionRequired: .permissionFlow; case .unavailable: .textInput }
    }
}

struct QuickLaunchRequestStore {
    private let defaults: UserDefaults
    private let key = "quick-launch.voice-requested"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func requestVoiceLaunch() { defaults.set(true, forKey: key) }
    func consumeVoiceLaunch() -> Bool {
        guard defaults.bool(forKey: key) else { return false }
        defaults.removeObject(forKey: key); return true
    }
}
