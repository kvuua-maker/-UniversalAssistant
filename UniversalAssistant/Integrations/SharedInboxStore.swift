import Foundation

struct SharedInboxEnvelope: Codable, Equatable, Sendable {
    let kind: String
    let value: String
    let receivedAt: Date
}

@MainActor
struct SharedInboxStore {
    static let suiteName = "group.com.universalassistant.shared"
    static let inboxKey = "pending-share-v1"
    let defaults: UserDefaults

    init(defaults: UserDefaults? = UserDefaults(suiteName: Self.suiteName)) {
        self.defaults = defaults ?? .standard
    }

    func consume() -> SharedInboxEnvelope? {
        guard let data = defaults.data(forKey: Self.inboxKey),
              let value = try? JSONDecoder().decode(SharedInboxEnvelope.self, from: data)
        else { return nil }
        defaults.removeObject(forKey: Self.inboxKey)
        return value
    }
}
