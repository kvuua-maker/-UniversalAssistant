import Foundation
import Testing
@testable import UniversalAssistant

struct PerformanceRecorderTests {
    @Test func boundedSamplesDiscardOldest() async throws {
        let recorder = PerformanceRecorder(capacity: 2)
        for _ in 0..<3 { _ = try await recorder.measure(.localParse) { 1 } }
        #expect(await recorder.snapshot().count == 2)
    }

    @Test func localParserBaseline() {
        let engine = LocalCommandEngine(); let clock = ContinuousClock(); let start = clock.now
        for _ in 0..<1_000 { _ = engine.parse("Знайди Baldinini 43 розміру до 12000 грн") }
        let elapsed = start.duration(to: clock.now)
        #expect(elapsed < .seconds(2), "Regression guard, not a device release budget")
    }
}
