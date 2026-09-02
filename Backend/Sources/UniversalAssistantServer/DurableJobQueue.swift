import Foundation

public enum ProactiveJobKind: String, Codable, Sendable {
    case trafficWatch, weatherWatch, productWatch, ticketWatch, parcelWatch, notificationDelivery
}

public struct ProactiveJob: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let kind: ProactiveJobKind
    public let sourceID: String
    public let deduplicationKey: String
    public let payload: Data
    public let createdAt: Date
    public let expiresAt: Date
    public var nextAttemptAt: Date
    public var attemptCount: Int

    public init(id: UUID = UUID(), kind: ProactiveJobKind, sourceID: String,
                deduplicationKey: String, payload: Data, createdAt: Date,
                expiresAt: Date, nextAttemptAt: Date? = nil, attemptCount: Int = 0) {
        self.id = id
        self.kind = kind
        self.sourceID = sourceID
        self.deduplicationKey = deduplicationKey
        self.payload = payload
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.nextAttemptAt = nextAttemptAt ?? createdAt
        self.attemptCount = attemptCount
    }
}

public struct DeadLetterJob: Codable, Equatable, Sendable {
    public let job: ProactiveJob
    public let reason: String
    public let failedAt: Date
}

public struct JobRetryPolicy: Equatable, Sendable {
    public let maximumAttempts: Int
    public let initialDelay: TimeInterval
    public let maximumDelay: TimeInterval
    public let jitterFraction: Double

    public init(maximumAttempts: Int = 4, initialDelay: TimeInterval = 5,
                maximumDelay: TimeInterval = 300, jitterFraction: Double = 0.2) {
        self.maximumAttempts = maximumAttempts
        self.initialDelay = initialDelay
        self.maximumDelay = maximumDelay
        self.jitterFraction = jitterFraction
    }

    func isValid() -> Bool {
        maximumAttempts > 0 && initialDelay > 0 && maximumDelay >= initialDelay &&
        (0...1).contains(jitterFraction)
    }

    func delay(after attempt: Int, jitterUnit: Double) -> TimeInterval {
        let exponential = min(maximumDelay, initialDelay * pow(2, Double(max(0, attempt - 1))))
        let boundedUnit = min(1, max(0, jitterUnit))
        return exponential * (1 + jitterFraction * boundedUnit)
    }
}

public enum DurableJobQueueError: Error, Equatable, Sendable {
    case invalidJob, invalidPolicy, unknownJob
}

public actor DurableJobQueue {
    private struct Snapshot: Codable {
        var queued: [ProactiveJob] = []
        var deadLetters: [DeadLetterJob] = []
        var completedDeduplicationKeys: Set<String> = []
    }

    private let fileURL: URL
    private let retryPolicy: JobRetryPolicy
    private var snapshot: Snapshot

    public init(fileURL: URL, retryPolicy: JobRetryPolicy = .init()) throws {
        guard retryPolicy.isValid() else { throw DurableJobQueueError.invalidPolicy }
        self.fileURL = fileURL
        self.retryPolicy = retryPolicy
        if FileManager.default.fileExists(atPath: fileURL.path) {
            snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: fileURL))
        } else {
            snapshot = Snapshot()
        }
    }

    @discardableResult
    public func enqueue(_ job: ProactiveJob, now: Date = .now) throws -> Bool {
        guard valid(job), job.expiresAt > now else { throw DurableJobQueueError.invalidJob }
        guard !snapshot.completedDeduplicationKeys.contains(job.deduplicationKey),
              !snapshot.queued.contains(where: { $0.deduplicationKey == job.deduplicationKey }) else { return false }
        snapshot.queued.append(job)
        try persist()
        return true
    }

    public func next(now: Date = .now) throws -> ProactiveJob? {
        expireJobs(now: now)
        try persist()
        return snapshot.queued
            .filter { $0.nextAttemptAt <= now }
            .sorted { lhs, rhs in
                lhs.nextAttemptAt == rhs.nextAttemptAt ? lhs.createdAt < rhs.createdAt : lhs.nextAttemptAt < rhs.nextAttemptAt
            }.first
    }

    public func complete(id: UUID) throws {
        guard let index = snapshot.queued.firstIndex(where: { $0.id == id }) else {
            throw DurableJobQueueError.unknownJob
        }
        snapshot.completedDeduplicationKeys.insert(snapshot.queued[index].deduplicationKey)
        snapshot.queued.remove(at: index)
        try persist()
    }

    public func fail(id: UUID, reason: String, now: Date = .now, jitterUnit: Double = 0) throws {
        guard let index = snapshot.queued.firstIndex(where: { $0.id == id }) else {
            throw DurableJobQueueError.unknownJob
        }
        snapshot.queued[index].attemptCount += 1
        if snapshot.queued[index].attemptCount >= retryPolicy.maximumAttempts || snapshot.queued[index].expiresAt <= now {
            let job = snapshot.queued.remove(at: index)
            snapshot.deadLetters.append(.init(job: job, reason: sanitized(reason), failedAt: now))
        } else {
            let delay = retryPolicy.delay(after: snapshot.queued[index].attemptCount, jitterUnit: jitterUnit)
            snapshot.queued[index].nextAttemptAt = now.addingTimeInterval(delay)
        }
        try persist()
    }

    @discardableResult
    public func cancel(sourceID: String) throws -> Int {
        let before = snapshot.queued.count
        snapshot.queued.removeAll { $0.sourceID == sourceID }
        try persist()
        return before - snapshot.queued.count
    }

    public func queuedJobs() -> [ProactiveJob] { snapshot.queued }
    public func deadLetters() -> [DeadLetterJob] { snapshot.deadLetters }

    private func valid(_ job: ProactiveJob) -> Bool {
        !job.sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !job.deduplicationKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        job.expiresAt > job.createdAt && job.attemptCount >= 0
    }

    private func expireJobs(now: Date) {
        let expired = snapshot.queued.filter { $0.expiresAt <= now }
        snapshot.queued.removeAll { $0.expiresAt <= now }
        snapshot.deadLetters.append(contentsOf: expired.map { .init(job: $0, reason: "expired", failedAt: now) })
    }

    private func sanitized(_ reason: String) -> String {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((trimmed.isEmpty ? "provider_error" : trimmed).prefix(160))
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
