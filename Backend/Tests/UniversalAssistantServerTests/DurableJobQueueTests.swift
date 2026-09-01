import Foundation
import Testing
@testable import UniversalAssistantServer

private func temporaryQueueURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("ua-job-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("queue.json")
}

private func proactiveJob(_ now: Date, key: String = "traffic:route-1",
                          sourceID: String = "rule-1", expiresIn: TimeInterval = 600) -> ProactiveJob {
    .init(kind: .trafficWatch, sourceID: sourceID, deduplicationKey: key,
          payload: Data("{}".utf8), createdAt: now, expiresAt: now.addingTimeInterval(expiresIn))
}

@Suite("Durable proactive job queue") struct DurableJobQueueTests {
    @Test func survivesRestartAndPreservesSourceLink() async throws {
        let url = temporaryQueueURL(), now = Date()
        let first = try DurableJobQueue(fileURL: url)
        try await first.enqueue(proactiveJob(now))
        let restored = try DurableJobQueue(fileURL: url)
        let job = try #require(try await restored.next(now: now))
        #expect(job.sourceID == "rule-1")
    }

    @Test func deduplicatesQueuedAndCompletedLogicalJobs() async throws {
        let queue = try DurableJobQueue(fileURL: temporaryQueueURL()), now = Date()
        let job = proactiveJob(now)
        #expect(try await queue.enqueue(job, now: now))
        #expect(try await !queue.enqueue(proactiveJob(now), now: now))
        try await queue.complete(id: job.id)
        #expect(try await !queue.enqueue(proactiveJob(now), now: now))
    }

    @Test func retriesAreBoundedThenMoveToDeadLetter() async throws {
        let policy = JobRetryPolicy(maximumAttempts: 2, initialDelay: 10, maximumDelay: 20, jitterFraction: 0.2)
        let queue = try DurableJobQueue(fileURL: temporaryQueueURL(), retryPolicy: policy), now = Date()
        let job = proactiveJob(now)
        try await queue.enqueue(job, now: now)
        try await queue.fail(id: job.id, reason: "temporary", now: now, jitterUnit: 1)
        let deferred = try #require(await queue.queuedJobs().first)
        #expect(deferred.nextAttemptAt == now.addingTimeInterval(12))
        try await queue.fail(id: job.id, reason: "still failing", now: now.addingTimeInterval(12))
        #expect(await queue.queuedJobs().isEmpty)
        #expect(await queue.deadLetters().first?.reason == "still failing")
    }

    @Test func expirationAndCancellationStopObsoleteWork() async throws {
        let queue = try DurableJobQueue(fileURL: temporaryQueueURL()), now = Date()
        let expiring = proactiveJob(now, key: "soon", sourceID: "old", expiresIn: 1)
        try await queue.enqueue(expiring, now: now)
        #expect(try await queue.next(now: now.addingTimeInterval(2)) == nil)
        #expect(await queue.deadLetters().first?.reason == "expired")
        try await queue.enqueue(proactiveJob(now, key: "new", sourceID: "cancel-me"), now: now)
        #expect(try await queue.cancel(sourceID: "cancel-me") == 1)
    }
}
