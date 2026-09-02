import Foundation

enum SpeechContentCategory: String, Codable, Sendable {
    case obviousProcessing, directActionNarration, usefulFact, ambiguity
    case warning, unverifiable, necessaryDecision, mandatorySafetyConfirmation
}

enum VoiceOutputPreference: String, Codable, Sendable {
    /// Speak only when the interaction context makes audio the natural channel.
    case contextual
    /// Never produce automatic speech; an explicit read/say request still wins.
    case screenOnly
}

enum VoiceInteractionContext: String, Codable, Sendable {
    case typed, voice, handsFree, navigation, screenNotPrimary
}

struct SpeechOutputRequest: Equatable, Sendable {
    let category: SpeechContentCategory
    let context: VoiceInteractionContext
    let isExplicitlyRequested: Bool
    let isLongResponse: Bool
}

struct SpeechOutputDecision: Equatable, Sendable {
    let speak: Bool
    let showOnScreen: Bool
    let reason: String
}

struct SpeechOutputPolicy: Sendable {
    func decide(_ request: SpeechOutputRequest, preference: VoiceOutputPreference = .contextual) -> SpeechOutputDecision {
        if request.category == .obviousProcessing || request.category == .directActionNarration {
            return .init(speak: false, showOnScreen: false, reason: "do_dont_narrate")
        }
        if request.isExplicitlyRequested {
            return .init(speak: true, showOnScreen: !request.isLongResponse, reason: "explicit_read_or_say")
        }
        if preference == .screenOnly {
            return .init(speak: false, showOnScreen: true, reason: "screen_only_preference")
        }
        if request.category == .warning || request.category == .mandatorySafetyConfirmation {
            return .init(speak: true, showOnScreen: true, reason: "short_critical_output")
        }
        let audioIsNatural = [.voice, .handsFree, .navigation, .screenNotPrimary].contains(request.context)
        guard audioIsNatural, !request.isLongResponse else {
            return .init(speak: false, showOnScreen: true, reason: request.isLongResponse ? "long_response_screen_default" : "screen_primary")
        }
        return .init(speak: true, showOnScreen: false, reason: "contextual_voice_output")
    }

    func shouldSpeak(_ category: SpeechContentCategory) -> Bool {
        decide(.init(category: category, context: .voice, isExplicitlyRequested: false, isLongResponse: false)).speak
    }
}

actor VoiceOutputPreferenceStore {
    private let store: LocalStore
    init(store: LocalStore = .shared) { self.store = store }
    func load() async throws -> VoiceOutputPreference {
        try await store.load(VoiceOutputPreference.self, from: "voice-output-preference.json") ?? .contextual
    }
    func save(_ preference: VoiceOutputPreference) async throws {
        try await store.save(preference, as: "voice-output-preference.json")
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
