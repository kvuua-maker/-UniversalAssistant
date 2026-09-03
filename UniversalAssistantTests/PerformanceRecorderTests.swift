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

    @Test func measuredPerformanceBudgetFailsMaterialRegression() {
        let budget = PerformanceBudget(metric: .endOfSpeechToLocalParse, baseline: 30,
                                       targetMaximum: 40, unit: "milliseconds",
                                       environmentReference: "iPhone-fixture")
        #expect(PerformanceBudgetEvaluator().evaluate(budget, measured: 39) == .pass)
        #expect(PerformanceBudgetEvaluator().evaluate(budget, measured: 41) == .fail(measured: 41, maximum: 40))
    }

    @Test func missingOrInvalidMeasurementCannotPassReleaseGate() {
        let budget = PerformanceBudget(metric: .coldLaunch, baseline: 1,
                                       targetMaximum: 2, unit: "seconds",
                                       environmentReference: "supported-device")
        #expect(PerformanceBudgetEvaluator().evaluate(budget, measured: nil) == .unavailable)
        #expect(!PerformanceBudgetEvaluator().releaseGate(budgets: [budget], measurements: [:]))
    }

    @Test func privacySafeProductMetricsAggregateRequiredOperationalSignals() async throws {
        let metrics = PrivacySafeProductMetrics()
        for event in [
            ProductMetricEvent(kind: .featureUsage, featureID: "weather"),
            ProductMetricEvent(kind: .featureUsage, featureID: "weather"),
            ProductMetricEvent(kind: .providerLatency, featureID: "weather", duration: .milliseconds(40)),
            ProductMetricEvent(kind: .connectorFailure, featureID: "weather"),
            ProductMetricEvent(kind: .connectorFallback, featureID: "weather"),
            ProductMetricEvent(kind: .crashSignal), ProductMetricEvent(kind: .coldLaunch, duration: .milliseconds(700)),
            ProductMetricEvent(kind: .voiceToCommand, duration: .milliseconds(120)),
            ProductMetricEvent(kind: .commandToAction, duration: .milliseconds(80)),
            ProductMetricEvent(kind: .memoryPressure)
        ] { await metrics.record(try #require(event)) }
        let snapshot = await metrics.snapshot()
        #expect(snapshot.featureUsage["weather"] == 2)
        #expect(snapshot.counts[.connectorFailure] == 1)
        #expect(snapshot.counts[.connectorFallback] == 1)
        #expect(snapshot.counts[.crashSignal] == 1)
        #expect(snapshot.counts[.memoryPressure] == 1)
        #expect(snapshot.durationTotals[.voiceToCommand] == .milliseconds(120))
        #expect(snapshot.durationTotals[.commandToAction] == .milliseconds(80))
    }

    @Test func productTelemetryRejectsUnboundedOrPrivateDimensions() {
        #expect(ProductMetricEvent(kind: .featureUsage, featureID: "raw command with spaces") == nil)
        #expect(ProductMetricEvent(kind: .providerLatency, duration: .milliseconds(-1)) == nil)
        #expect(ProductMetricEvent(kind: .featureUsage, featureID: String(repeating: "a", count: 65)) == nil)
    }
}
