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

    @Test @MainActor func wrongResultUserActionPersistsOnlyPrivacySafeMetadataEndToEnd() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ua-feedback-action-\(UUID().uuidString)", isDirectory: true)
        let store = UserFeedbackStore(localStore: LocalStore(baseDirectory: directory))
        let model = AssistantViewModel(feedbackStore: store)
        let sensitiveCommand = "Покажи приватний запит із секретом 779"
        model.input = sensitiveCommand
        model.submit()

        let record = try #require(await model.reportWrongResult())
        let reloaded = UserFeedbackStore(localStore: LocalStore(baseDirectory: directory))
        #expect(try await reloaded.records() == [record])
        #expect(record.category == .wrongResult)
        #expect(model.statusText.contains(record.diagnosticID))

        let data = try Data(contentsOf: directory.appendingPathComponent("feedback-queue.json"))
        let raw = try #require(String(data: data, encoding: .utf8))
        #expect(!raw.contains(sensitiveCommand))
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(Set(try #require(payload.first).keys) == ["diagnosticID", "category", "createdAt"])
    }
}
