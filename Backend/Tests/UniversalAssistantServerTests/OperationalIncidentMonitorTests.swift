import Foundation
import Testing
@testable import UniversalAssistantServer

@Suite("Operational incident monitoring")
struct OperationalIncidentMonitorTests {
    @Test func persistentFailuresOpenOneAlertAndRecoveryClosesIt() async throws {
        let monitor = try OperationalIncidentMonitor(failureThreshold: 2), now = Date()
        #expect(await monitor.record(.transientFailure, for: .database, now: now) == nil)
        let opened = try #require(await monitor.record(
            .transientFailure, for: .database, now: now.addingTimeInterval(1)
        ))
        #expect(opened.kind == .opened)
        #expect(OperationalIncidentMonitor.validDiagnosticID(opened.diagnosticID))
        #expect(await monitor.record(.criticalFailure, for: .database, now: now) == nil)
        #expect(await monitor.health(for: .database) == .unavailable)
        #expect(await monitor.userStatusKey() == "service_temporarily_degraded")

        let recovered = try #require(await monitor.record(
            .success, for: .database, now: now.addingTimeInterval(2)
        ))
        #expect(recovered.kind == .recovered)
        #expect(recovered.diagnosticID == opened.diagnosticID)
        #expect(await monitor.health(for: .database) == .healthy)
        #expect(await monitor.alertHistory().count == 2)
    }

    @Test func dependenciesDegradeIndependentlyAndCriticalFailureAlertsImmediately() async throws {
        let monitor = try OperationalIncidentMonitor(failureThreshold: 3)
        let alert = try #require(await monitor.record(.criticalFailure, for: .persistentQueue))
        #expect(alert.dependency == .persistentQueue)
        #expect(await monitor.health(for: .apns) == .healthy)
    }

    @Test func feedbackContainsOnlyDiagnosticCategoryAndTime() throws {
        let report = try MinimizedFeedbackReport(
            diagnosticID: "UA-123456789ABC", category: "wrong_result",
            occurredAt: Date(timeIntervalSince1970: 1)
        )
        let object = try #require(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(report)
        ) as? [String: Any])
        #expect(Set(object.keys) == ["diagnosticID", "category", "occurredAt"])
        #expect(!object.keys.contains("rawCommand"))
        #expect(!object.keys.contains("providerPayload"))
    }
}
