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
