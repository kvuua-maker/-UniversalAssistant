import Foundation

public enum DeliveryEventOutcome: String, Codable, Sendable { case accepted, invalidToken, retryable, rejected }
public struct DeliveryEvent: Codable, Equatable, Sendable {
    public let notificationID: UUID; public let outcome: DeliveryEventOutcome
    public let statusCode: Int?; public let reason: String?; public let occurredAt: Date
}
public enum DependencyHealth: String, Codable, Equatable, Sendable { case healthy, degraded, unavailable }
public struct NotificationHealth: Equatable, Sendable {
    public let apns: DependencyHealth; public let recentFailures: Int; public let lastEventAt: Date?
}

public actor NotificationObservability {
    private struct Snapshot: Codable { var events: [DeliveryEvent] = [] }
    private let fileURL: URL; private let capacity: Int; private var snapshot: Snapshot
    public init(fileURL: URL, capacity: Int = 500) throws {
        guard capacity > 0 else { throw ObservabilityError.invalidCapacity }
        self.fileURL = fileURL; self.capacity = capacity
        snapshot = FileManager.default.fileExists(atPath: fileURL.path)
            ? try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: fileURL)) : Snapshot()
    }
    public func record(notificationID: UUID, outcome: APNSDeliveryOutcome, now: Date = .now) throws {
        let event: DeliveryEvent
        switch outcome {
        case .accepted: event = .init(notificationID: notificationID, outcome: .accepted, statusCode: 200, reason: nil, occurredAt: now)
        case .invalidToken: event = .init(notificationID: notificationID, outcome: .invalidToken, statusCode: 410, reason: "invalid_token", occurredAt: now)
        case let .retryable(code): event = .init(notificationID: notificationID, outcome: .retryable, statusCode: code, reason: "transient_apns_failure", occurredAt: now)
        case let .rejected(code, reason): event = .init(notificationID: notificationID, outcome: .rejected, statusCode: code, reason: String(reason.prefix(80)), occurredAt: now)
        }
        snapshot.events.append(event)
        if snapshot.events.count > capacity { snapshot.events.removeFirst(snapshot.events.count - capacity) }
        try persist()
    }
    public func health(since: Date) -> NotificationHealth {
        let recent = snapshot.events.filter { $0.occurredAt >= since }
        let failures = recent.filter { $0.outcome == .retryable || $0.outcome == .rejected }.count
        let state: DependencyHealth = recent.isEmpty ? .unavailable : (failures * 2 >= recent.count ? .degraded : .healthy)
        return .init(apns: state, recentFailures: failures, lastEventAt: recent.last?.occurredAt)
    }
    public func events() -> [DeliveryEvent] { snapshot.events }
    private func persist() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
    public enum ObservabilityError: Error { case invalidCapacity }
}
