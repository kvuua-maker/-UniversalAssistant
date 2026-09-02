import Foundation
import Testing
@testable import UniversalAssistant

struct RuntimeExperiencePolicyTests {
    @Test func speechNeverNarratesObviousWorkButAllowsNecessaryContent() {
        let policy = SpeechOutputPolicy()
        #expect(!policy.shouldSpeak(.obviousProcessing))
        #expect(!policy.shouldSpeak(.directActionNarration))
        #expect(policy.shouldSpeak(.usefulFact))
        #expect(policy.shouldSpeak(.ambiguity))
        #expect(policy.shouldSpeak(.warning))
        #expect(policy.shouldSpeak(.unverifiable))
        #expect(policy.shouldSpeak(.necessaryDecision))
        #expect(policy.shouldSpeak(.mandatorySafetyConfirmation))
    }

    @Test func ordinaryAndLongInformationDefaultsToScreenWithoutAutomaticSpeech() {
        let policy = SpeechOutputPolicy()
        let ordinary = policy.decide(.init(category: .usefulFact, context: .typed, isExplicitlyRequested: false, isLongResponse: false))
        let longVoice = policy.decide(.init(category: .usefulFact, context: .voice, isExplicitlyRequested: false, isLongResponse: true))
        #expect(ordinary == .init(speak: false, showOnScreen: true, reason: "screen_primary"))
        #expect(longVoice == .init(speak: false, showOnScreen: true, reason: "long_response_screen_default"))
    }

    @Test func naturalVoiceContextsAndExplicitReadUseSpeechWithoutFullDuplication() {
        let policy = SpeechOutputPolicy()
        let handsFree = policy.decide(.init(category: .usefulFact, context: .handsFree, isExplicitlyRequested: false, isLongResponse: false))
        let explicit = policy.decide(.init(category: .usefulFact, context: .typed, isExplicitlyRequested: true, isLongResponse: true))
        #expect(handsFree == .init(speak: true, showOnScreen: false, reason: "contextual_voice_output"))
        #expect(explicit == .init(speak: true, showOnScreen: false, reason: "explicit_read_or_say"))
    }

    @Test func directActionsAreNeverNarratedEvenWhenVoiceWasUsed() {
        let decision = SpeechOutputPolicy().decide(.init(category: .directActionNarration, context: .voice, isExplicitlyRequested: false, isLongResponse: false))
        #expect(decision == .init(speak: false, showOnScreen: false, reason: "do_dont_narrate"))
    }

    @Test func voicePreferencePersistsAndScreenOnlySuppressesAutomaticSpeech() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let store = VoiceOutputPreferenceStore(store: LocalStore(baseDirectory: directory))
        #expect(try await store.load() == .contextual)
        try await store.save(.screenOnly)
        #expect(try await store.load() == .screenOnly)
        let decision = SpeechOutputPolicy().decide(
            .init(category: .usefulFact, context: .handsFree, isExplicitlyRequested: false, isLongResponse: false),
            preference: .screenOnly
        )
        #expect(!decision.speak && decision.showOnScreen)
    }

    @Test func coffeeActivatesOnlyCanonicalMinimalPath() throws {
        let command = LocalCommandEngine().parse("Хочу кави")
        #expect(command.intent == .placeSearch)
        #expect(try DeterministicExecutionPlanBuilder().activationPath(for: command) == [.voice, .command, .location, .places, .route])
    }

    @Test func unrelatedProviderModulesStayOutOfSimplePaths() throws {
        let command = LocalCommandEngine().parse("Відкрий Telegram")
        #expect(try DeterministicExecutionPlanBuilder().activationPath(for: command) == [.voice, .command, .directAction])
    }

    @Test func confirmedHomeAndWorkAreReusedOnlyWhileFresh() {
        let now = Date(timeIntervalSince1970: 100)
        let provenance = ContextProvenance(source: "owner-confirmed", objectID: "home", observedAt: now, expiresAt: now.addingTimeInterval(60))
        let home = ContextEntity(id: "home-id", kind: .place, displayName: "Home", phoneNumber: nil, provenance: provenance)
        var context = CurrentContext()
        context.update(now: now, lifetime: 60, results: [home], preferences: ["place.home": "home-id"])
        #expect(context.savedPlace(named: "HOME", now: now)?.id == "home-id")
        #expect(context.savedPlace(named: "home", now: now.addingTimeInterval(61)) == nil)
    }

    @Test func explicitTaxiRuleBecomesDeterministicRequestWithoutClarification() {
        let preference = TaxiPreference(mode: .cheapest, maximumWaitMinutes: 7)
        let request = KnownPreferenceResolver().taxiRequest(from: preference)
        #expect(request.mode == .cheapest)
        #expect(request.maximumWaitSeconds == 420)
    }

    @Test func resourcePressureTightensConcurrencyCacheAndLocation() {
        let policy = RuntimeResourcePolicy()
        let normal = policy.limits(for: .init(lowPowerMode: false, memoryPressure: false, constrainedNetwork: false))
        let pressured = policy.limits(for: .init(lowPowerMode: false, memoryPressure: true, constrainedNetwork: false))
        #expect(normal == .init(maximumParallelProviders: 6, maximumCacheEntries: 32, permitHighAccuracyLocation: true))
        #expect(pressured == .init(maximumParallelProviders: 1, maximumCacheEntries: 1, permitHighAccuracyLocation: false))
    }
}
