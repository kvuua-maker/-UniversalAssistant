import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Affiliate program status registry") struct AffiliateProgramRegistryTests {
    private func registry(_ directory: URL) -> AffiliateProgramRegistry { AffiliateProgramRegistry(store: LocalStore(baseDirectory: directory)) }

    @Test func orderedStatusPersistsAcrossRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ua-affiliate-\(UUID())")
        let first = registry(directory)
        _ = try await first.register(id: "network:merchant", providerID: "merchant")
        _ = try await first.transition(id: "network:merchant", to: .applicationRequired)
        _ = try await first.transition(id: "network:merchant", to: .applied, evidence: .init(reference: "application-1", kind: "application", recordedAt: .now, provesConversionAttribution: false))
        let restored = registry(directory); try await restored.restore()
        #expect(await restored.record(id: "network:merchant")?.status == .applied)
    }

    @Test func cannotSkipStatesOrClaimEarningFromClick() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ua-affiliate-\(UUID())")
        let value = registry(directory); _ = try await value.register(id: "p", providerID: "p")
        await #expect(throws: AffiliateProgramRegistryError.invalidTransition) { try await value.transition(id: "p", to: .approved) }
        for status in [AffiliateProgramStatus.applicationRequired, .applied, .approved, .credentialsReceived, .implemented, .testVerified, .productionVerified] { _ = try await value.transition(id: "p", to: status) }
        let click = AffiliateProgramEvidence(reference: "click-1", kind: "click", recordedAt: .now, provesConversionAttribution: false)
        await #expect(throws: AffiliateProgramRegistryError.earningEvidenceRequired) { try await value.transition(id: "p", to: .earningVerified, evidence: click) }
        #expect(await value.record(id: "p")?.status == .productionVerified)
    }
}
