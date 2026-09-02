import Foundation
import Testing
@testable import UniversalAssistantServer

private actor ProviderCleanupFixture: AccountProviderConnectionCleaning {
    let shouldFail: Bool
    init(shouldFail: Bool) { self.shouldFail = shouldFail }
    func revokeAndDeleteConnections(userID: String) throws -> Int {
        if shouldFail { throw URLError(.cannotConnectToHost) }
        return 2
    }
}

@Suite("Account deletion cleanup integration")
struct AccountDeletionCleanupTests {
    @Test func deletionCancelsOnlyAccountJobsTokensAndProviderConnections() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let queue = try DurableJobQueue(fileURL: root.appendingPathComponent("jobs.json"))
        let tokens = try APNSDeviceTokenRegistry(fileURL: root.appendingPathComponent("tokens.json"))
        let now = Date()
        for user in ["delete-me", "keep-me"] {
            try await queue.enqueue(.init(kind: .productWatch, sourceID: user, deduplicationKey: user,
                payload: Data(), createdAt: now, expiresAt: now.addingTimeInterval(600)), now: now)
        }
        try await tokens.register(userID: "delete-me", deviceID: "phone", token: Data(repeating: 1, count: 32), environment: .sandbox)
        try await tokens.register(userID: "keep-me", deviceID: "other-phone", token: Data(repeating: 2, count: 32), environment: .sandbox)
        let service = AccountDeletionCleanupService(jobs: queue, tokens: tokens,
                                                     providers: ProviderCleanupFixture(shouldFail: false))
        let report = await service.deleteAccount(userID: "delete-me")
        #expect(report.isComplete)
        #expect(report.cancelledJobs == 1 && report.removedPushTokens == 1 && report.removedProviderConnections == 2)
        #expect(await queue.queuedJobs().map(\.sourceID) == ["keep-me"])
        #expect(await tokens.registrations(userID: "keep-me", environment: .sandbox).count == 1)
    }

    @Test func partialFailureIsReportedWithoutFakeSuccess() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let service = AccountDeletionCleanupService(
            jobs: try DurableJobQueue(fileURL: root.appendingPathComponent("jobs.json")),
            tokens: try APNSDeviceTokenRegistry(fileURL: root.appendingPathComponent("tokens.json")),
            providers: ProviderCleanupFixture(shouldFail: true))
        let report = await service.deleteAccount(userID: "user")
        #expect(!report.isComplete)
        #expect(report.failedSteps == ["provider_connections"])
        #expect(report.cancelledJobs == 0 && report.removedPushTokens == 0)
    }
}
