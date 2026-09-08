import Foundation
import Testing
@testable import UniversalAssistant

struct QuickLaunchPolicyTests {
    private let policy = QuickLaunchPolicy()

    @Test func actionButtonIsPrimaryOnlyWhenActuallyAvailable() {
        let available = capabilities(action: .available)
        #expect(policy.recommendedMechanisms(available).first == .actionButton)
        let unavailable = capabilities(action: .unavailable)
        #expect(!policy.recommendedMechanisms(unavailable).contains(.actionButton))
        #expect(policy.recommendedMechanisms(unavailable).first == .backTap)
    }

    @Test func supportedAlternativesAndUnsupportedCapabilitiesAreTruthful() {
        let values = policy.recommendedMechanisms(capabilities(action: .unavailable))
        #expect(values == [.backTap, .appShortcut, .homeScreenShortcut, .assistiveTouch])
        let limited = QuickLaunchCapabilities(actionButton: .unavailable, backTap: .unavailable, appShortcut: .available, homeScreenShortcut: .unavailable, assistiveTouch: .unavailable)
        #expect(policy.recommendedMechanisms(limited) == [.appShortcut])
    }

    @Test func launchRoutesDirectlyWithoutNarrationOrExtraTap() {
        #expect(policy.destination(voice: .permitted) == .listening)
        #expect(policy.destination(voice: .permissionRequired) == .permissionFlow)
        #expect(policy.destination(voice: .unavailable) == .textInput)
    }

    @Test func launchRequestIsPersistentAndConsumedOnce() {
        let suite = "quick-launch-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = QuickLaunchRequestStore(defaults: defaults)
        store.requestVoiceLaunch()
        #expect(store.consumeVoiceLaunch())
        #expect(!store.consumeVoiceLaunch())
    }

    @Test func canonicalCommandRequestIsTrimmedPersistentAndConsumedOnce() {
        let suite = "quick-launch-command-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = QuickLaunchRequestStore(defaults: defaults)
        store.requestCommand("  Порахуй сім помножити на девʼять  ")
        #expect(store.consumeCommand() == "Порахуй сім помножити на девʼять")
        #expect(store.consumeCommand() == nil)
        store.requestCommand("   ")
        #expect(store.consumeCommand() == nil)
    }

    private func capabilities(action: SystemCapabilityAvailability) -> QuickLaunchCapabilities {
        .init(actionButton: action, backTap: .available, appShortcut: .available, homeScreenShortcut: .available, assistiveTouch: .available)
    }
}
