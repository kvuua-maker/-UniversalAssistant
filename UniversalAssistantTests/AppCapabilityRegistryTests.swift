import Foundation
import Testing
@testable import UniversalAssistant

private func appRecord(id: String = "maps", capabilities: AppCapabilities = [.openApp, .navigate], mechanisms: Set<AppIntegrationMechanism> = [.universalLink], regions: Set<String> = ["UA"], minimumVersion: String? = nil) -> AppCapabilityRecord {
    .init(id: id, displayName: id, bundleIdentifier: "com.example.\(id)", regions: regions, minimumVersion: minimumVersion, capabilities: capabilities, mechanisms: mechanisms, supportedActions: ["navigate"], authenticationRequired: false, limitations: [], fallback: [.openApp], testStatus: .documented, officialDocumentationURL: URL(string: "https://example.com/docs/\(id)"), lastOfficialVerification: Date())
}
@Suite("Universal app capability registry") struct AppCapabilityRegistryTests {
    @Test func regionVersionAndCapabilityAreHardFilters() async throws {
        let registry = try AppCapabilityRegistry(records: [appRecord(minimumVersion: "3.2")])
        #expect(await registry.eligible(region: "UA", capability: .navigate, installedVersion: "3.1").isEmpty)
        #expect(await registry.eligible(region: "UA", capability: .navigate, installedVersion: "3.2").map(\.id) == ["maps"])
    }
    @Test func deepestVerifiedMechanismWins() async throws {
        let registry = try AppCapabilityRegistry(records: [appRecord(mechanisms: [.urlScheme, .appIntent, .api])])
        let route = try await registry.deepestRoute(appID: "maps", capability: .navigate)
        #expect(route.0 == .api)
    }

    @Test func canonicalPriorityIncludesEveryLegitimateFallbackDepth() async throws {
        let mechanisms: Set<AppIntegrationMechanism> = [.instruction, .navigation, .phone, .officialWeb,
            .structuredFeed, .urlScheme, .universalLink, .shortcut, .appIntent, .oauthPartnerAPI, .sdk, .api]
        let registry = try AppCapabilityRegistry(records: [appRecord(mechanisms: mechanisms)])
        #expect(try await registry.deepestRoute(appID: "maps", capability: .navigate).0 == .api)

        let fallback = try AppCapabilityRegistry(records: [appRecord(mechanisms: [.instruction, .phone, .officialWeb])])
        #expect(try await fallback.deepestRoute(appID: "maps", capability: .navigate).0 == .officialWeb)
    }
    @Test func openOnlyCannotPretendToDeeperAutomation() async {
        #expect(throws: AppCapabilityRegistryError.invalidRecord) { _ = try AppCapabilityRegistry(records: [appRecord(capabilities: [.openApp, .send], mechanisms: [.openOnly])]) }
    }
    @Test func officialEvidenceIsMandatory() async {
        let bad = AppCapabilityRecord(id: "bad", displayName: "Bad", bundleIdentifier: nil, regions: ["UA"], minimumVersion: nil, capabilities: [.openApp], mechanisms: [.openOnly], supportedActions: [], authenticationRequired: false, limitations: [], fallback: [], testStatus: .documented, officialDocumentationURL: nil, lastOfficialVerification: nil)
        #expect(throws: AppCapabilityRegistryError.invalidRecord) { _ = try AppCapabilityRegistry(records: [bad]) }
    }
}
