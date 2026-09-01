import Foundation

enum PerformanceMetric: String, Codable, Sendable { case localParse, firstUsefulResult, coldLaunch, warmLaunch }

struct PerformanceSample: Codable, Equatable, Sendable {
    let metric: PerformanceMetric
    let duration: Duration
    let recordedAt: Date
}

actor PerformanceRecorder {
    private let capacity: Int
    private var samples: [PerformanceSample] = []
    init(capacity: Int = 100) { self.capacity = max(1, capacity) }
    func measure<T: Sendable>(_ metric: PerformanceMetric, operation: @Sendable () async throws -> T) async rethrows -> T {
        let clock = ContinuousClock(); let start = clock.now
        let result = try await operation()
        record(PerformanceSample(metric: metric, duration: start.duration(to: clock.now), recordedAt: .now))
        return result
    }
    func record(_ sample: PerformanceSample) {
        samples.append(sample)
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
    }
    func snapshot() -> [PerformanceSample] { samples }
}
