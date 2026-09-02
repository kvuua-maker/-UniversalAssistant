import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Privacy-safe user feedback")
struct UserFeedbackStoreTests {
    @Test func recordPersistsOnlyBoundedDiagnosticMetadata() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ua-feedback-\(UUID().uuidString)", isDirectory: true)
        let store = UserFeedbackStore(localStore: LocalStore(baseDirectory: directory))
        let record = try await store.record(.wrongResult, now: Date(timeIntervalSince1970: 1))
        #expect(record.diagnosticID.hasPrefix("UA-"))
        #expect(try await store.records() == [record])
        let data = try Data(contentsOf: directory.appendingPathComponent("feedback-queue.json"))
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("rawCommand"))
        #expect(!text.contains("providerPayload"))
    }
}
