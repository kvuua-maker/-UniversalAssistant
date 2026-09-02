import Foundation

public enum OperationalDependency: String, Codable, CaseIterable, Sendable {
    case backend, persistentQueue, apns, database, provider
}

public enum OperationalSignal: String, Codable, Sendable {
    case success, transientFailure, criticalFailure
}

public enum OperationalAlertKind: String, Codable, Sendable {
    case opened, recovered
}

public struct OperationalAlert: Codable, Equatable, Sendable {
    public let dependency: OperationalDependency
    public let kind: OperationalAlertKind
    public let diagnosticID: String
    public let occurredAt: Date
}

public struct MinimizedFeedbackReport: Codable, Equatable, Sendable {
    public let diagnosticID: String
    public let category: String
    public let occurredAt: Date

    public init(diagnosticID: String, category: String, occurredAt: Date = .now) throws {
        guard OperationalIncidentMonitor.validDiagnosticID(diagnosticID),
              ["wrong_result", "not_what_i_meant", "service_problem"].contains(category) else {
            throw OperationalMonitorError.invalidFeedback
        }
        self.diagnosticID = diagnosticID
        self.category = category
        self.occurredAt = occurredAt
    }
}

public enum OperationalMonitorError: Error, Equatable, Sendable {
    case invalidThreshold, invalidFeedback
}

public actor OperationalIncidentMonitor {
    private let failureThreshold: Int
    private var consecutiveFailures: [OperationalDependency: Int] = [:]
    private var openIncidents: [OperationalDependency: String] = [:]
    private var alerts: [OperationalAlert] = []

    public init(failureThreshold: Int = 3) throws {
        guard failureThreshold > 0 else { throw OperationalMonitorError.invalidThreshold }
        self.failureThreshold = failureThreshold
    }

    public func record(_ signal: OperationalSignal, for dependency: OperationalDependency,
                       now: Date = .now) -> OperationalAlert? {
        switch signal {
        case .success:
            consecutiveFailures[dependency] = 0
            guard let diagnosticID = openIncidents.removeValue(forKey: dependency) else { return nil }
            return append(.init(dependency: dependency, kind: .recovered,
                                diagnosticID: diagnosticID, occurredAt: now))
        case .transientFailure, .criticalFailure:
            consecutiveFailures[dependency, default: 0] += 1
            let shouldOpen = signal == .criticalFailure ||
                consecutiveFailures[dependency, default: 0] >= failureThreshold
            guard shouldOpen, openIncidents[dependency] == nil else { return nil }
            let diagnosticID = Self.makeDiagnosticID()
            openIncidents[dependency] = diagnosticID
            return append(.init(dependency: dependency, kind: .opened,
                                diagnosticID: diagnosticID, occurredAt: now))
        }
    }

    public func health(for dependency: OperationalDependency) -> DependencyHealth {
        if openIncidents[dependency] != nil { return .unavailable }
        return consecutiveFailures[dependency, default: 0] > 0 ? .degraded : .healthy
    }

    public func userStatusKey() -> String? {
        openIncidents.isEmpty ? nil : "service_temporarily_degraded"
    }

    public func alertHistory() -> [OperationalAlert] { alerts }

    public static func validDiagnosticID(_ value: String) -> Bool {
        value.hasPrefix("UA-") && value.count == 15 &&
        value.dropFirst(3).allSatisfy { $0.isHexDigit }
    }

    private static func makeDiagnosticID() -> String {
        "UA-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).uppercased()
    }

    private func append(_ alert: OperationalAlert) -> OperationalAlert {
        alerts.append(alert)
        return alert
    }
}
