import Foundation

public enum ProactiveWatchKind: String, Codable, Sendable {
    case traffic, weather, businessHours, product, ticket, parcel

    var jobKind: ProactiveJobKind {
        switch self {
        case .traffic: .trafficWatch
        case .weather: .weatherWatch
        case .product: .productWatch
        case .ticket: .ticketWatch
        case .parcel: .parcelWatch
        case .businessHours: .notificationDelivery
        }
    }
}

public struct ProactiveWatchRule: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let userID: String
    public let subjectID: String
    public let kind: ProactiveWatchKind
    public let minimumMeaningfulChange: Double
    public let checkInterval: TimeInterval
    public let createdAt: Date
    public let expiresAt: Date
    public var nextCheckAt: Date
    public var enabled: Bool

    public init(id: UUID = UUID(), userID: String, subjectID: String, kind: ProactiveWatchKind,
                minimumMeaningfulChange: Double = 0, checkInterval: TimeInterval,
                createdAt: Date, expiresAt: Date, nextCheckAt: Date? = nil, enabled: Bool = true) {
        self.id = id; self.userID = userID; self.subjectID = subjectID; self.kind = kind
        self.minimumMeaningfulChange = minimumMeaningfulChange; self.checkInterval = checkInterval
        self.createdAt = createdAt; self.expiresAt = expiresAt
        self.nextCheckAt = nextCheckAt ?? createdAt; self.enabled = enabled
    }
}

public struct ProactiveObservation: Codable, Equatable, Sendable {
    public let numericValue: Double?
    public let state: String?
    public let source: String
    public let observedAt: Date
    public init(numericValue: Double? = nil, state: String? = nil, source: String, observedAt: Date) {
        self.numericValue = numericValue; self.state = state; self.source = source; self.observedAt = observedAt
    }
}

public struct ProactiveWatchTrigger: Equatable, Sendable {
    public let ruleID: UUID
    public let userID: String
    public let category: NotificationCategory
    public let eventKey: String
    public let contentVersion: String
}

public enum ProactiveWatchError: Error, Equatable, Sendable { case invalidRule, unknownRule, staleObservation }

public actor ProactiveWatchEngine {
    private struct Snapshot: Codable {
        var rules: [ProactiveWatchRule] = []
        var observations: [UUID: ProactiveObservation] = [:]
    }
    private let fileURL: URL
    private let maximumObservationAge: TimeInterval
    private var snapshot: Snapshot

    public init(fileURL: URL, maximumObservationAge: TimeInterval = 15 * 60) throws {
        self.fileURL = fileURL; self.maximumObservationAge = maximumObservationAge
        if FileManager.default.fileExists(atPath: fileURL.path) {
            snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: fileURL))
        } else { snapshot = Snapshot() }
    }

    public func add(_ rule: ProactiveWatchRule, now: Date = .now) throws {
        guard valid(rule), rule.expiresAt > now else { throw ProactiveWatchError.invalidRule }
        snapshot.rules.removeAll { $0.id == rule.id }
        snapshot.rules.append(rule); try persist()
    }

    public func dueJobs(now: Date = .now) throws -> [ProactiveJob] {
        snapshot.rules.removeAll { $0.expiresAt <= now }
        var jobs: [ProactiveJob] = []
        for index in snapshot.rules.indices where snapshot.rules[index].enabled && snapshot.rules[index].nextCheckAt <= now {
            let rule = snapshot.rules[index]
            let bucket = Int(now.timeIntervalSince1970 / rule.checkInterval)
            jobs.append(.init(kind: rule.kind.jobKind, sourceID: rule.id.uuidString,
                              deduplicationKey: "watch:\(rule.id):\(bucket)", payload: Data(rule.subjectID.utf8),
                              createdAt: now, expiresAt: min(rule.expiresAt, now.addingTimeInterval(rule.checkInterval))))
            snapshot.rules[index].nextCheckAt = now.addingTimeInterval(rule.checkInterval)
        }
        try persist(); return jobs
    }

    public func record(ruleID: UUID, observation: ProactiveObservation, now: Date = .now) throws -> ProactiveWatchTrigger? {
        guard let rule = snapshot.rules.first(where: { $0.id == ruleID && $0.enabled }), rule.expiresAt > now else {
            throw ProactiveWatchError.unknownRule
        }
        let age = now.timeIntervalSince(observation.observedAt)
        guard !observation.source.isEmpty, age >= -60, age <= maximumObservationAge else {
            throw ProactiveWatchError.staleObservation
        }
        let previous = snapshot.observations[ruleID]
        if let previous, !meaningful(rule: rule, previous: previous, current: observation) {
            return nil
        }
        snapshot.observations[ruleID] = observation
        try persist()
        guard previous != nil else { return nil }
        return .init(ruleID: rule.id, userID: rule.userID, category: category(rule.kind),
                     eventKey: rule.subjectID, contentVersion: fingerprint(observation))
    }

    @discardableResult
    public func cancel(ruleID: UUID) throws -> Bool {
        let before = snapshot.rules.count
        snapshot.rules.removeAll { $0.id == ruleID }; snapshot.observations[ruleID] = nil
        try persist(); return before != snapshot.rules.count
    }

    public func rules(userID: String) -> [ProactiveWatchRule] { snapshot.rules.filter { $0.userID == userID } }

    private func meaningful(rule: ProactiveWatchRule, previous: ProactiveObservation, current: ProactiveObservation) -> Bool {
        if let old = previous.numericValue, let new = current.numericValue,
           abs(new - old) >= rule.minimumMeaningfulChange { return true }
        return previous.state != current.state && current.state != nil
    }
    private func category(_ kind: ProactiveWatchKind) -> NotificationCategory {
        switch kind { case .traffic: .traffic; case .weather: .weather; case .product: .product; case .ticket: .ticket; case .parcel: .parcel; case .businessHours: .business }
    }
    private func fingerprint(_ value: ProactiveObservation) -> String {
        let number = value.numericValue.map { String($0) } ?? "-"
        let state = value.state ?? "-"
        let timestamp = Int(value.observedAt.timeIntervalSince1970)
        return "\(number):\(state):\(timestamp)"
    }
    private func valid(_ rule: ProactiveWatchRule) -> Bool {
        !rule.userID.isEmpty && !rule.subjectID.isEmpty && rule.minimumMeaningfulChange >= 0 &&
        rule.checkInterval >= 60 && rule.expiresAt > rule.createdAt
    }
    private func persist() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
