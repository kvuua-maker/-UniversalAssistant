import Foundation
import Testing
@testable import UniversalAssistantServer

private func notice(_ now: Date, version: String = "v1", expires: TimeInterval = 300,
                    category: NotificationCategory = .traffic,
                    route: String = "universalassistant://open/task/route-1") -> ProactiveNotification {
    .init(userID: "user", category: category, eventKey: "route-1", contentVersion: version,
          collapseID: "traffic:route-1", threadID: "traffic", exactRoute: route,
          createdAt: now, expiresAt: now.addingTimeInterval(expires))
}

@Suite("Proactive notification policy") struct NotificationPolicyTests {
    @Test func preferencesSuppressGloballyAndByCategory() async throws {
        let now = Date(), engine = NotificationPolicyEngine()
        await engine.setPreferences(.init(userID: "user", enabledCategories: [.weather]))
        #expect(try await engine.evaluate(notice(now), now: now) == .suppressed(reason: "category_disabled"))
        await engine.setPreferences(.init(userID: "user", notificationsEnabled: false))
        #expect(try await engine.evaluate(notice(now), now: now) == .suppressed(reason: "notifications_disabled"))
    }

    @Test func identicalMeaningfulEventIsDeduplicated() async throws {
        let now = Date(), engine = NotificationPolicyEngine(), value = notice(now)
        guard case .deliver = try await engine.evaluate(value, now: now) else { Issue.record("expected delivery"); return }
        #expect(try await engine.evaluate(value, now: now) == .suppressed(reason: "duplicate"))
    }

    @Test func newerVersionReplacesThroughSameCollapseID() async throws {
        let now = Date(), engine = NotificationPolicyEngine(), first = notice(now)
        _ = try await engine.evaluate(first, now: now)
        let decision = try await engine.evaluate(notice(now, version: "v2"), now: now)
        guard case let .replace(previousID, replacement) = decision else { Issue.record("expected replacement"); return }
        #expect(previousID == first.id)
        #expect(replacement.contentVersion == "v2")
    }

    @Test func expiredNotificationNeverDelivers() async throws {
        let now = Date(), engine = NotificationPolicyEngine()
        #expect(try await engine.evaluate(notice(now, expires: 1), now: now.addingTimeInterval(2)) == .suppressed(reason: "expired"))
    }

    @Test func homeOrWebRouteIsRejected() async throws {
        let now = Date(), engine = NotificationPolicyEngine()
        await #expect(throws: NotificationPolicyError.invalidNotification) {
            try await engine.evaluate(notice(now, route: "https://example.com/"), now: now)
        }
    }
}
