import Foundation

enum OwnerTestDeliveryChannel: String, Codable, CaseIterable, Sendable { case localXcode, adHoc, testFlight, enterprise }

struct OwnerTestDeliveryConstraints: Equatable, Sendable {
    let selectedChannel: OwnerTestDeliveryChannel?
    let signingVerified: Bool
    let requiredMembershipVerified: Bool
    let physicalDeviceAvailable: Bool
}

enum OwnerTestDeliveryDecision: Equatable, Sendable {
    case notConfigured
    case ready(OwnerTestDeliveryChannel)
    case ownerDecisionRequired(String)
}

struct OwnerTestDeliveryPolicy: Sendable {
    func decide(_ constraints: OwnerTestDeliveryConstraints) -> OwnerTestDeliveryDecision {
        guard let channel = constraints.selectedChannel else { return .notConfigured }
        guard constraints.signingVerified else { return .ownerDecisionRequired("Signing capability is not verified") }
        if channel == .testFlight && !constraints.requiredMembershipVerified {
            return .ownerDecisionRequired("TestFlight membership is not verified")
        }
        if channel == .localXcode && !constraints.physicalDeviceAvailable {
            return .ownerDecisionRequired("A physical device is not available")
        }
        return .ready(channel)
    }
}

struct OwnerTestBuild: Codable, Equatable, Sendable {
    let buildNumber: Int
    let commit: String
    let includedFeatures: [String]
    let regressionTestIDs: [String]
    let issuedAt: Date
    let channel: OwnerTestDeliveryChannel
}

enum OwnerTestBuildRegistryError: Error, Equatable {
    case invalidBuildNumber, reusedBuildNumber, nonMonotonicBuildNumber
}

actor OwnerTestBuildRegistry {
    private let store: LocalStore
    private let fileName: String

    init(store: LocalStore = .shared, fileName: String = "owner-test-builds.json") {
        self.store = store
        self.fileName = fileName
    }

    func issue(_ build: OwnerTestBuild) async throws {
        guard build.buildNumber > 0 else { throw OwnerTestBuildRegistryError.invalidBuildNumber }
        var builds = try await allBuilds()
        if let existing = builds.first(where: { $0.buildNumber == build.buildNumber }) {
            guard existing == build else { throw OwnerTestBuildRegistryError.reusedBuildNumber }
            return
        }
        guard build.buildNumber > (builds.map(\.buildNumber).max() ?? 0) else {
            throw OwnerTestBuildRegistryError.nonMonotonicBuildNumber
        }
        builds.append(build)
        try await store.save(builds, as: fileName)
    }

    func allBuilds() async throws -> [OwnerTestBuild] {
        try await store.load([OwnerTestBuild].self, from: fileName) ?? []
    }
}
