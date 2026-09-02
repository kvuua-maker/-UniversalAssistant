import Foundation
import Testing
@testable import UniversalAssistantServer

@Suite("Notification delivery observability") struct NotificationObservabilityTests {
    @Test func persistsBoundedRedactedEvents() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ua-obs-\(UUID())/events.json")
        let log = try NotificationObservability(fileURL: url, capacity: 2)
        try await log.record(notificationID: UUID(), outcome: .accepted(apnsID: "private-provider-id"))
        try await log.record(notificationID: UUID(), outcome: .retryable(statusCode: 500))
        try await log.record(notificationID: UUID(), outcome: .invalidToken)
        let restored = try NotificationObservability(fileURL: url, capacity: 2)
        let events = await restored.events()
        #expect(events.count == 2)
        #expect(events.allSatisfy { $0.reason != "private-provider-id" })
    }
    @Test func healthDegradesSelectivelyFromRecentFailures() async throws {
        let now = Date(), log = try NotificationObservability(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("ua-obs-\(UUID())/events.json"))
        try await log.record(notificationID: UUID(), outcome: .retryable(statusCode: 503), now: now)
        #expect(await log.health(since: now.addingTimeInterval(-1)).apns == .degraded)
        #expect(await log.health(since: now.addingTimeInterval(1)).apns == .unavailable)
    }
}
