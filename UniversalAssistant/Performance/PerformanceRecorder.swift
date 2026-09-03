import Foundation

enum PerformanceMetric: String, Codable, Sendable {
    case localParse
    case intentResolution
    case coordinationPlanning
    case provider
    case parallelCriticalPath
    case firstUsefulResult
    case totalCompletion
    case aiFallback
    case coldLaunch
    case warmLaunch
}

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

enum AIFallbackReason: String, Codable, Equatable, Sendable {
    case unresolvedSemanticAmbiguity
    case complexNaturalLanguageInterpretation
    case complexVerifiedResultSynthesis
}

struct AICostMetadata: Codable, Equatable, Sendable {
    let amount: Decimal
    let currencyCode: String

    init?(amount: Decimal, currencyCode: String) {
        let normalizedCurrency = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard amount >= 0,
              normalizedCurrency.count == 3,
              normalizedCurrency.unicodeScalars.allSatisfy(CharacterSet.uppercaseLetters.contains)
        else { return nil }
        self.amount = amount
        self.currencyCode = normalizedCurrency
    }
}

/// Aggregate measurements for one coordination run. Deliberately excludes raw
/// commands, provider payloads, URLs, account identifiers and other user data.
struct CoordinationObservation: Codable, Equatable, Sendable {
    let intentResolution: Duration
    let planning: Duration
    let providerLatency: Duration
    let parallelCriticalPath: Duration
    let timeToFirstUsefulResult: Duration
    let totalCompletion: Duration
    let providerCallCount: Int
    let cancelledProviderCallCount: Int
    let aiInvocationCount: Int
    let aiLatency: Duration?
    let aiInputTokenCount: Int?
    let aiOutputTokenCount: Int?
    let aiCost: AICostMetadata?
    let aiFallbackReason: AIFallbackReason?
    let recordedAt: Date

    init?(
        intentResolution: Duration,
        planning: Duration,
        providerLatency: Duration,
        parallelCriticalPath: Duration,
        timeToFirstUsefulResult: Duration,
        totalCompletion: Duration,
        providerCallCount: Int,
        cancelledProviderCallCount: Int,
        aiInvocationCount: Int,
        aiLatency: Duration? = nil,
        aiInputTokenCount: Int? = nil,
        aiOutputTokenCount: Int? = nil,
        aiCost: AICostMetadata? = nil,
        aiFallbackReason: AIFallbackReason? = nil,
        recordedAt: Date = .now
    ) {
        let durations = [intentResolution, planning, providerLatency, parallelCriticalPath,
                         timeToFirstUsefulResult, totalCompletion]
        guard durations.allSatisfy({ $0 >= .zero }),
              providerCallCount >= 0,
              cancelledProviderCallCount >= 0,
              cancelledProviderCallCount <= providerCallCount,
              (0...1).contains(aiInvocationCount),
              aiInputTokenCount.map({ $0 >= 0 }) ?? true,
              aiOutputTokenCount.map({ $0 >= 0 }) ?? true
        else { return nil }

        let hasAIMetadata = aiLatency != nil || aiInputTokenCount != nil || aiOutputTokenCount != nil || aiCost != nil || aiFallbackReason != nil
        guard aiInvocationCount == 1 || !hasAIMetadata,
              aiLatency.map({ $0 >= .zero }) ?? true
        else { return nil }

        self.intentResolution = intentResolution
        self.planning = planning
        self.providerLatency = providerLatency
        self.parallelCriticalPath = parallelCriticalPath
        self.timeToFirstUsefulResult = timeToFirstUsefulResult
        self.totalCompletion = totalCompletion
        self.providerCallCount = providerCallCount
        self.cancelledProviderCallCount = cancelledProviderCallCount
        self.aiInvocationCount = aiInvocationCount
        self.aiLatency = aiLatency
        self.aiInputTokenCount = aiInputTokenCount
        self.aiOutputTokenCount = aiOutputTokenCount
        self.aiCost = aiCost
        self.aiFallbackReason = aiFallbackReason
        self.recordedAt = recordedAt
    }
}

actor CoordinationObservabilityRecorder {
    private let capacity: Int
    private var observations: [CoordinationObservation] = []

    init(capacity: Int = 100) { self.capacity = max(1, capacity) }

    func record(_ observation: CoordinationObservation) {
        observations.append(observation)
        if observations.count > capacity {
            observations.removeFirst(observations.count - capacity)
        }
    }

    func snapshot() -> [CoordinationObservation] { observations }
}

enum ProductMetricKind: String, Codable, CaseIterable, Sendable {
    case featureUsage
    case commandLatency
    case providerLatency
    case connectorFailure
    case connectorFallback
    case crashSignal
    case coldLaunch
    case warmLaunch
    case voiceToCommand
    case commandToAction
    case memoryPressure
}

/// Privacy-safe product telemetry. Dimensions are bounded enums/registered
/// feature identifiers; raw commands, URLs, payloads and user identifiers are
/// intentionally absent from the contract.
struct ProductMetricEvent: Equatable, Codable, Sendable {
    let kind: ProductMetricKind
    let featureID: String?
    let duration: Duration?
    let recordedAt: Date

    init?(kind: ProductMetricKind, featureID: String? = nil, duration: Duration? = nil, recordedAt: Date = .now) {
        let normalized = featureID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.map({ !$0.isEmpty && $0.count <= 64 && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } }) ?? true,
              duration.map({ $0 >= .zero }) ?? true else { return nil }
        self.kind = kind; self.featureID = normalized; self.duration = duration; self.recordedAt = recordedAt
    }
}

struct ProductMetricsSnapshot: Equatable, Sendable {
    let counts: [ProductMetricKind: Int]
    let featureUsage: [String: Int]
    let durationTotals: [ProductMetricKind: Duration]
}

actor PrivacySafeProductMetrics {
    private var counts: [ProductMetricKind: Int] = [:]
    private var featureUsage: [String: Int] = [:]
    private var durationTotals: [ProductMetricKind: Duration] = [:]

    func record(_ event: ProductMetricEvent) {
        counts[event.kind, default: 0] += 1
        if event.kind == .featureUsage, let feature = event.featureID { featureUsage[feature, default: 0] += 1 }
        if let duration = event.duration { durationTotals[event.kind, default: .zero] += duration }
    }

    func snapshot() -> ProductMetricsSnapshot {
        .init(counts: counts, featureUsage: featureUsage, durationTotals: durationTotals)
    }
}

enum PerformanceBudgetMetric: String, Codable, CaseIterable, Sendable {
    case coldLaunch, warmLaunch, actionButtonToListening, endOfSpeechToLocalParse
    case firstNetworkResult, normalRAM, selectedCPU, selectedBattery
}

struct PerformanceBudget: Equatable, Codable, Sendable {
    let metric: PerformanceBudgetMetric
    let baseline: Decimal
    let targetMaximum: Decimal
    let unit: String
    let environmentReference: String
}

enum PerformanceBudgetVerdict: Equatable, Sendable {
    case pass
    case fail(measured: Decimal, maximum: Decimal)
    case unavailable
}

struct PerformanceBudgetEvaluator: Sendable {
    func evaluate(_ budget: PerformanceBudget, measured: Decimal?) -> PerformanceBudgetVerdict {
        guard budget.baseline >= 0, budget.targetMaximum >= 0,
              !budget.unit.isEmpty, !budget.environmentReference.isEmpty,
              let measured, measured >= 0 else { return .unavailable }
        return measured <= budget.targetMaximum ? .pass : .fail(measured: measured, maximum: budget.targetMaximum)
    }

    func releaseGate(budgets: [PerformanceBudget], measurements: [PerformanceBudgetMetric: Decimal]) -> Bool {
        !budgets.isEmpty && budgets.allSatisfy { evaluate($0, measured: measurements[$0.metric]) == .pass }
    }
}
