import Foundation
import Testing
@testable import UniversalAssistantServer

private func watchURL() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("ua-watch-\(UUID())/state.json") }
private func rule(_ now: Date, kind: ProactiveWatchKind = .traffic, threshold: Double = 5) -> ProactiveWatchRule {
    .init(userID: "user", subjectID: "subject", kind: kind, minimumMeaningfulChange: threshold,
          checkInterval: 60, createdAt: now, expiresAt: now.addingTimeInterval(600))
}

@Suite("Proactive watch orchestration") struct ProactiveWatchEngineTests {
    @Test func dueWatchCreatesLinkedDeduplicableJobAndPersistsSchedule() async throws {
        let now = Date(), url = watchURL(), engine = try ProactiveWatchEngine(fileURL: url), value = rule(now)
        try await engine.add(value, now: now)
        let job = try #require(try await engine.dueJobs(now: now).first)
        #expect(job.sourceID == value.id.uuidString)
        #expect(job.deduplicationKey.hasPrefix("watch:\(value.id):"))
        let restored = try ProactiveWatchEngine(fileURL: url)
        #expect(try await restored.dueJobs(now: now).isEmpty)
    }

    @Test func onlyMeaningfulFreshChangeTriggersNotification() async throws {
        let now = Date(), engine = try ProactiveWatchEngine(fileURL: watchURL()), value = rule(now)
        try await engine.add(value, now: now)
        #expect(try await engine.record(ruleID: value.id, observation: .init(numericValue: 10, source: "provider", observedAt: now), now: now) == nil)
        #expect(try await engine.record(ruleID: value.id, observation: .init(numericValue: 12, source: "provider", observedAt: now), now: now) == nil)
        #expect(try await engine.record(ruleID: value.id, observation: .init(numericValue: 16, source: "provider", observedAt: now), now: now)?.category == .traffic)
    }

    @Test func staleObservationIsRejected() async throws {
        let now = Date(), engine = try ProactiveWatchEngine(fileURL: watchURL()), value = rule(now)
        try await engine.add(value, now: now)
        await #expect(throws: ProactiveWatchError.staleObservation) {
            try await engine.record(ruleID: value.id, observation: .init(state: "changed", source: "provider", observedAt: now.addingTimeInterval(-2_000)), now: now)
        }
    }

    @Test func naturalCancellationRemovesRuleAndObservation() async throws {
        let now = Date(), engine = try ProactiveWatchEngine(fileURL: watchURL()), value = rule(now, kind: .product)
        try await engine.add(value, now: now)
        #expect(try await engine.cancel(ruleID: value.id))
        #expect(await engine.rules(userID: "user").isEmpty)
        #expect(try await engine.dueJobs(now: now).isEmpty)
    }

    @Test func parcelWatchPersistsAcrossRestartAndTriggersOnlyOnChangedProviderState() async throws {
        let now = Date(), url = watchURL()
        let value = ProactiveWatchRule(userID: "parcel-user", subjectID: "novaPoshta:20400000000000",
            kind: .parcel, checkInterval: 60, createdAt: now,
            expiresAt: now.addingTimeInterval(30 * 24 * 3_600))
        let engine = try ProactiveWatchEngine(fileURL: url)
        try await engine.add(value, now: now)
        let job = try #require(try await engine.dueJobs(now: now).first)
        #expect(job.kind == .parcelWatch)
        #expect(String(decoding: job.payload, as: UTF8.self) == value.subjectID)

        let restored = try ProactiveWatchEngine(fileURL: url)
        let persisted = try #require(await restored.rules(userID: "parcel-user").first)
        #expect(persisted.id == value.id)
        #expect(persisted.kind == .parcel)
        #expect(persisted.subjectID == value.subjectID)
        #expect(persisted.nextCheckAt == now.addingTimeInterval(value.checkInterval))
        #expect(try await restored.record(ruleID: value.id,
            observation: .init(state: "at_branch", source: "novaPoshta:event-1", observedAt: now), now: now) == nil)
        #expect(try await restored.record(ruleID: value.id,
            observation: .init(state: "at_branch", source: "novaPoshta:event-1", observedAt: now), now: now) == nil)
        let trigger = try await restored.record(ruleID: value.id,
            observation: .init(state: "delivered", source: "novaPoshta:event-2", observedAt: now), now: now)
        #expect(trigger?.category == .parcel)
        #expect(trigger?.eventKey == value.subjectID)
    }
}
