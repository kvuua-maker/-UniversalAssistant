import Foundation

enum SpeechContentCategory: Sendable {
    case obviousProcessing, directActionNarration, usefulFact, ambiguity
    case warning, unverifiable, necessaryDecision, mandatorySafetyConfirmation
}

struct SpeechOutputPolicy: Sendable {
    func shouldSpeak(_ category: SpeechContentCategory) -> Bool {
        switch category {
        case .obviousProcessing, .directActionNarration: false
        case .usefulFact, .ambiguity, .warning, .unverifiable, .necessaryDecision, .mandatorySafetyConfirmation: true
        }
    }
}

struct TaxiPreference: Equatable, Codable, Sendable {
    let mode: ComparisonMode
    let maximumWaitMinutes: Int?
}

struct KnownPreferenceResolver: Sendable {
    func taxiRequest(from preference: TaxiPreference) -> RideComparisonRequest {
        .init(mode: preference.mode, maximumWaitSeconds: preference.maximumWaitMinutes.map { TimeInterval($0 * 60) })
    }
}

struct ResourceConditions: Equatable, Sendable {
    let lowPowerMode: Bool
    let memoryPressure: Bool
    let constrainedNetwork: Bool
}

struct ResourceLimits: Equatable, Sendable {
    let maximumParallelProviders: Int
    let maximumCacheEntries: Int
    let permitHighAccuracyLocation: Bool
}

struct RuntimeResourcePolicy: Sendable {
    func limits(for conditions: ResourceConditions) -> ResourceLimits {
        if conditions.memoryPressure {
            return .init(maximumParallelProviders: 1, maximumCacheEntries: 1, permitHighAccuracyLocation: false)
        }
        if conditions.lowPowerMode || conditions.constrainedNetwork {
            return .init(maximumParallelProviders: 2, maximumCacheEntries: 8, permitHighAccuracyLocation: false)
        }
        return .init(maximumParallelProviders: 6, maximumCacheEntries: 32, permitHighAccuracyLocation: true)
    }
}
