import Foundation

public enum NotificationCategory: String, Codable, CaseIterable, Sendable {
    case traffic, weather, product, ticket, parcel, business
}

public struct NotificationPreferences: Codable, Equatable, Sendable {
    public let userID: String
    public var enabledCategories: Set<NotificationCategory>
    public var notificationsEnabled: Bool

    public init(userID: String, enabledCategories: Set<NotificationCategory> = Set(NotificationCategory.allCases),
                notificationsEnabled: Bool = true) {
        self.userID = userID
        self.enabledCategories = enabledCategories
        self.notificationsEnabled = notificationsEnabled
    }
}

public struct ProactiveNotification: Codable, Equatable, Sendable {
    public let id: UUID
    public let userID: String
    public let category: NotificationCategory
    public let eventKey: String
    public let contentVersion: String
    public let collapseID: String
    public let threadID: String
    public let exactRoute: String
    public let createdAt: Date
    public let expiresAt: Date

    public init(id: UUID = UUID(), userID: String, category: NotificationCategory,
                eventKey: String, contentVersion: String, collapseID: String,
                threadID: String, exactRoute: String, createdAt: Date, expiresAt: Date) {
        self.id = id; self.userID = userID; self.category = category
        self.eventKey = eventKey; self.contentVersion = contentVersion
        self.collapseID = collapseID; self.threadID = threadID; self.exactRoute = exactRoute
        self.createdAt = createdAt; self.expiresAt = expiresAt
    }
}

public enum NotificationPolicyDecision: Equatable, Sendable {
    case deliver(ProactiveNotification)
    case replace(previousID: UUID, with: ProactiveNotification)
    case suppressed(reason: String)
}

public enum NotificationPolicyError: Error, Equatable, Sendable { case invalidNotification }

public actor NotificationPolicyEngine {
    private var preferences: [String: NotificationPreferences] = [:]
    private var acceptedByEvent: [String: ProactiveNotification] = [:]

    public init() {}

    public func setPreferences(_ value: NotificationPreferences) {
        preferences[value.userID] = value
    }

    public func evaluate(_ notification: ProactiveNotification, now: Date = .now) throws -> NotificationPolicyDecision {
        guard valid(notification) else { throw NotificationPolicyError.invalidNotification }
        guard notification.expiresAt > now else { return .suppressed(reason: "expired") }
        let preference = preferences[notification.userID] ?? .init(userID: notification.userID)
        guard preference.notificationsEnabled else { return .suppressed(reason: "notifications_disabled") }
        guard preference.enabledCategories.contains(notification.category) else {
            return .suppressed(reason: "category_disabled")
        }
        let key = "\(notification.userID):\(notification.category.rawValue):\(notification.eventKey)"
        if let previous = acceptedByEvent[key] {
            guard previous.contentVersion != notification.contentVersion else {
                return .suppressed(reason: "duplicate")
            }
            guard previous.collapseID == notification.collapseID else {
                return .suppressed(reason: "collapse_mismatch")
            }
            acceptedByEvent[key] = notification
            return .replace(previousID: previous.id, with: notification)
        }
        acceptedByEvent[key] = notification
        return .deliver(notification)
    }

    private func valid(_ value: ProactiveNotification) -> Bool {
        let fields = [value.userID, value.eventKey, value.contentVersion, value.collapseID, value.threadID]
        guard fields.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 128 }),
              value.expiresAt > value.createdAt,
              let components = URLComponents(string: value.exactRoute),
              components.scheme == "universalassistant",
              components.host == "open",
              !components.path.isEmpty, components.path != "/" else { return false }
        return true
    }
}
