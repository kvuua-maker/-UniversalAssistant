import Foundation

struct DevelopmentHeartbeat: Codable, Equatable, Sendable {
    let currentBlock: String; let currentAction: String; let status: String
    let lastMeasurableProgress: String; let attemptPathID: String; let lastCommit: String; let blocker: String?
    enum CodingKeys: String, CodingKey {
        case currentBlock = "current_block", currentAction = "current_action", status
        case lastMeasurableProgress = "last_measurable_progress", attemptPathID = "attempt_path_id"
        case lastCommit = "last_commit", blocker
    }
}

enum DevelopmentWatchdogFinding: Equatable, Sendable {
    case healthy, malformedHeartbeat, inconsistentDashboard
    case stale(lastProgress: Date, action: String)
}

struct DevelopmentStateWatchdog: Sendable {
    func inspect(heartbeatData: Data, projectStatus: String, now: Date, staleAfter: TimeInterval = 1_800) -> DevelopmentWatchdogFinding {
        guard let heartbeat = try? JSONDecoder().decode(DevelopmentHeartbeat.self, from: heartbeatData),
              let progress = ISO8601DateFormatter().date(from: heartbeat.lastMeasurableProgress), staleAfter > 0 else { return .malformedHeartbeat }
        guard projectStatus.contains("Current block/action:"),
              projectStatus.contains("STALLED: YES") || projectStatus.contains("STALLED: NO"),
              projectStatus.localizedCaseInsensitiveContains(heartbeat.currentAction.replacingOccurrences(of: "-", with: " ")) else { return .inconsistentDashboard }
        if now.timeIntervalSince(progress) > staleAfter && heartbeat.status != "LONG_RUNNING" {
            return .stale(lastProgress: progress, action: heartbeat.currentAction)
        }
        return .healthy
    }
}
