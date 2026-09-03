import Foundation

enum AppAppearance: String, Codable, CaseIterable, Sendable { case automatic, dark, light }
enum AppAccent: String, Codable, CaseIterable, Sendable { case purple, blue, cyan, green, amber, pink }
enum AnimationLevel: String, Codable, CaseIterable, Sendable { case system, reduced, full }

struct PresentationPreferences: Codable, Equatable, Sendable {
    var appearance: AppAppearance = .automatic
    var accent: AppAccent = .purple
    var animationLevel: AnimationLevel = .system
    var voiceOutput: VoiceOutputPreference = .contextual
}

actor PresentationPreferenceStore {
    private let store: LocalStore
    private let filename: String
    init(store: LocalStore = .shared, filename: String = "presentation-preferences.json") {
        self.store = store; self.filename = filename
    }
    func load() async throws -> PresentationPreferences {
        try await store.load(PresentationPreferences.self, from: filename) ?? .init()
    }
    func save(_ value: PresentationPreferences) async throws {
        try await store.save(value, as: filename)
    }
}
