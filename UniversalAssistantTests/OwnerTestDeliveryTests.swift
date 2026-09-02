import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Owner test delivery") struct OwnerTestDeliveryTests {
    @Test func deliveryChannelIsNeverAssumed() {
        let policy = OwnerTestDeliveryPolicy()
        #expect(policy.decide(.init(selectedChannel: nil, signingVerified: false, requiredMembershipVerified: false, physicalDeviceAvailable: false)) == .notConfigured)
        #expect(policy.decide(.init(selectedChannel: .testFlight, signingVerified: true, requiredMembershipVerified: false, physicalDeviceAvailable: true)) == .ownerDecisionRequired("TestFlight membership is not verified"))
        #expect(policy.decide(.init(selectedChannel: .localXcode, signingVerified: true, requiredMembershipVerified: true, physicalDeviceAvailable: true)) == .ready(.localXcode))
    }

    @Test func issuedBuildsArePersistentMonotonicAndImmutable() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let registry = OwnerTestBuildRegistry(store: LocalStore(baseDirectory: directory))
        let first = OwnerTestBuild(buildNumber: 7, commit: "abc", includedFeatures: ["voice"], regressionTestIDs: ["VOICE-001"], issuedAt: Date(timeIntervalSince1970: 1), channel: .localXcode)
        try await registry.issue(first)
        try await registry.issue(first)
        #expect(try await registry.allBuilds() == [first])
        let changed = OwnerTestBuild(buildNumber: 7, commit: "def", includedFeatures: ["voice"], regressionTestIDs: ["VOICE-001"], issuedAt: Date(timeIntervalSince1970: 1), channel: .localXcode)
        await #expect(throws: OwnerTestBuildRegistryError.reusedBuildNumber) { try await registry.issue(changed) }
        let lower = OwnerTestBuild(buildNumber: 6, commit: "abc", includedFeatures: [], regressionTestIDs: [], issuedAt: Date(timeIntervalSince1970: 2), channel: .localXcode)
        await #expect(throws: OwnerTestBuildRegistryError.nonMonotonicBuildNumber) { try await registry.issue(lower) }
    }
}
