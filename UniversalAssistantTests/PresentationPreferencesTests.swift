import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Presentation preferences") struct PresentationPreferencesTests {
    @Test func defaultsRespectSystemAndContextualVoice() async throws {
        let store = PresentationPreferenceStore(store: LocalStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("ua-prefs-\(UUID())")))
        let value = try await store.load()
        #expect(value.appearance == .automatic)
        #expect(value.voiceOutput == .contextual)
        #expect(value.animationLevel == .system)
    }

    @Test func appearanceAccentAnimationAndVoicePersist() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ua-prefs-\(UUID())")
        let first = PresentationPreferenceStore(store: LocalStore(baseDirectory: directory))
        let value = PresentationPreferences(appearance: .dark, accent: .cyan, animationLevel: .reduced, voiceOutput: .screenOnly)
        try await first.save(value)
        let restored = PresentationPreferenceStore(store: LocalStore(baseDirectory: directory))
        #expect(try await restored.load() == value)
    }
}
