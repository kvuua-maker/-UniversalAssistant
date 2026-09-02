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

    @Test func deterministicCoordinationRecordsZeroAIAndExactProviderCounts() async throws {
        let recorder = CoordinationObservabilityRecorder()
        let observation = try #require(CoordinationObservation(
            intentResolution: .milliseconds(2), planning: .milliseconds(3),
            providerLatency: .milliseconds(40), parallelCriticalPath: .milliseconds(28),
            timeToFirstUsefulResult: .milliseconds(18), totalCompletion: .milliseconds(47),
            providerCallCount: 5, cancelledProviderCallCount: 1, aiInvocationCount: 0
        ))
        await recorder.record(observation)
        let recorded = try #require(await recorder.snapshot().first)
        #expect(recorded.providerCallCount == 5)
        #expect(recorded.cancelledProviderCallCount == 1)
        #expect(recorded.aiInvocationCount == 0)
        #expect(recorded.aiFallbackReason == nil)
    }

    @Test func boundedAIObservationKeepsTypedOptionalCostMetadata() throws {
        let cost = try #require(AICostMetadata(amount: Decimal(string: "0.0012")!, currencyCode: "usd"))
        let observation = try #require(CoordinationObservation(
            intentResolution: .milliseconds(2), planning: .milliseconds(4),
            providerLatency: .zero, parallelCriticalPath: .zero,
            timeToFirstUsefulResult: .milliseconds(20), totalCompletion: .milliseconds(90),
            providerCallCount: 0, cancelledProviderCallCount: 0, aiInvocationCount: 1,
            aiLatency: .milliseconds(65), aiInputTokenCount: 42, aiOutputTokenCount: 12,
            aiCost: cost, aiFallbackReason: .unresolvedSemanticAmbiguity
        ))
        #expect(observation.aiCost?.currencyCode == "USD")
        #expect(observation.aiFallbackReason == .unresolvedSemanticAmbiguity)
    }

    @Test func rejectsInconsistentOrUnboundedTelemetry() {
        #expect(CoordinationObservation(
            intentResolution: .zero, planning: .zero, providerLatency: .zero,
            parallelCriticalPath: .zero, timeToFirstUsefulResult: .zero, totalCompletion: .zero,
            providerCallCount: 1, cancelledProviderCallCount: 2, aiInvocationCount: 0
        ) == nil)
        #expect(CoordinationObservation(
            intentResolution: .zero, planning: .zero, providerLatency: .zero,
            parallelCriticalPath: .zero, timeToFirstUsefulResult: .zero, totalCompletion: .zero,
            providerCallCount: 0, cancelledProviderCallCount: 0, aiInvocationCount: 2
        ) == nil)
        #expect(CoordinationObservation(
            intentResolution: .zero, planning: .zero, providerLatency: .zero,
            parallelCriticalPath: .zero, timeToFirstUsefulResult: .zero, totalCompletion: .zero,
            providerCallCount: 0, cancelledProviderCallCount: 0, aiInvocationCount: 0,
            aiFallbackReason: .complexNaturalLanguageInterpretation
        ) == nil)
    }

    @Test func coordinationObservationsAreBoundedAndContainNoRawCommandField() async throws {
        let recorder = CoordinationObservabilityRecorder(capacity: 2)
        for offset in 0..<3 {
            let observation = try #require(CoordinationObservation(
                intentResolution: .milliseconds(offset), planning: .zero, providerLatency: .zero,
                parallelCriticalPath: .zero, timeToFirstUsefulResult: .zero, totalCompletion: .zero,
                providerCallCount: 0, cancelledProviderCallCount: 0, aiInvocationCount: 0
            ))
            await recorder.record(observation)
        }
        let snapshot = await recorder.snapshot()
        #expect(snapshot.count == 2)
        let encoded = try JSONEncoder().encode(snapshot)
        let json = try #require(String(data: encoded, encoding: .utf8))
        #expect(!json.contains("commandText"))
        #expect(!json.contains("providerPayload"))
        #expect(!json.contains("userIdentifier"))
    }
}
