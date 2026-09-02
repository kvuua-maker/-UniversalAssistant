import Foundation
import Testing
@testable import UniversalAssistant

private struct LegacyPreference: Codable { let locale: String }
private struct CurrentPreference: Codable, Equatable, Sendable { let locale: String; let notificationsEnabled: Bool }

@Suite("Versioned local persistence")
struct LocalStoreMigrationTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "ua-store-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    @Test func representativeOlderSchemaMigratesAndRewritesAtomically() async throws {
        let store = LocalStore(baseDirectory: directory())
        try await store.saveVersioned(LegacyPreference(locale: "uk"), schemaVersion: 1, as: "preferences.json")
        let result = try await store.loadVersioned(CurrentPreference.self, currentVersion: 2, from: "preferences.json") { version, payload in
            #expect(version == 1)
            let legacy = try JSONDecoder().decode(LegacyPreference.self, from: payload)
            return CurrentPreference(locale: legacy.locale, notificationsEnabled: true)
        }
        guard case .migrated(let value, fromVersion: 1) = result else { Issue.record("Expected migration"); return }
        #expect(value == CurrentPreference(locale: "uk", notificationsEnabled: true))
        let reloaded = try await store.loadVersioned(CurrentPreference.self, currentVersion: 2, from: "preferences.json") { _, _ in
            throw LocalStoreVersionError.invalidVersion
        }
        guard case .loaded(let value) = reloaded else { Issue.record("Expected current schema"); return }
        #expect(value.locale == "uk")
    }

    @Test func corruptStoreIsQuarantinedInsteadOfSilentlyOverwritten() async throws {
        let directory = directory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "preferences.json")
        try Data("not-json".utf8).write(to: file)
        let store = LocalStore(baseDirectory: directory)
        let result = try await store.loadVersioned(CurrentPreference.self, currentVersion: 2, from: "preferences.json") { _, _ in
            throw LocalStoreVersionError.invalidVersion
        }
        guard case .quarantinedCorruption(let quarantine) = result else { Issue.record("Expected quarantine"); return }
        #expect(FileManager.default.fileExists(atPath: quarantine.path))
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func futureSchemaIsRejectedWithoutMovingData() async throws {
        let directory = directory(), store = LocalStore(baseDirectory: directory)
        try await store.saveVersioned(CurrentPreference(locale: "uk", notificationsEnabled: true), schemaVersion: 3, as: "preferences.json")
        await #expect(throws: LocalStoreVersionError.futureVersion) {
            try await store.loadVersioned(CurrentPreference.self, currentVersion: 2, from: "preferences.json") { _, _ in
                throw LocalStoreVersionError.invalidVersion
            }
        }
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "preferences.json").path))
    }
}
