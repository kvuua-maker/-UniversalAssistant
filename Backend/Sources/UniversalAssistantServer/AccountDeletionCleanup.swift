import Foundation

public protocol AccountProviderConnectionCleaning: Sendable {
    func revokeAndDeleteConnections(userID: String) async throws -> Int
}

public struct AccountDeletionCleanupReport: Equatable, Sendable {
    public let cancelledJobs: Int?
    public let removedPushTokens: Int?
    public let removedProviderConnections: Int?
    public let failedSteps: [String]
    public var isComplete: Bool { failedSteps.isEmpty }
}

public actor AccountDeletionCleanupService {
    private let jobs: DurableJobQueue
    private let tokens: APNSDeviceTokenRegistry
    private let providers: any AccountProviderConnectionCleaning

    public init(jobs: DurableJobQueue, tokens: APNSDeviceTokenRegistry,
                providers: any AccountProviderConnectionCleaning) {
        self.jobs = jobs; self.tokens = tokens; self.providers = providers
    }

    public func deleteAccount(userID: String) async -> AccountDeletionCleanupReport {
        let trimmed = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 128 else {
            return .init(cancelledJobs: nil, removedPushTokens: nil,
                         removedProviderConnections: nil, failedSteps: ["invalid_user"])
        }
        async let jobResult = capture("proactive_jobs") { try await self.jobs.cancel(sourceID: trimmed) }
        async let tokenResult = capture("push_tokens") { try await self.tokens.logout(userID: trimmed) }
        async let providerResult = capture("provider_connections") {
            try await self.providers.revokeAndDeleteConnections(userID: trimmed)
        }
        let values = await [jobResult, tokenResult, providerResult]
        return .init(cancelledJobs: values[0].value, removedPushTokens: values[1].value,
                     removedProviderConnections: values[2].value,
                     failedSteps: values.compactMap(\.failure))
    }

    private func capture(_ name: String, operation: @escaping @Sendable () async throws -> Int) async -> (value: Int?, failure: String?) {
        do { return (try await operation(), nil) }
        catch { return (nil, name) }
    }
}
