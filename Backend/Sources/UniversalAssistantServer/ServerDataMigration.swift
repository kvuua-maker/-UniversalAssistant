import Foundation

struct ServerSchemaState: Codable, Equatable, Sendable {
    var version: Int
    var records: [String: [String: String]]
}

struct ServerMigrationStep: Sendable {
    let fromVersion: Int
    let toVersion: Int
    let transform: @Sendable (ServerSchemaState) throws -> ServerSchemaState
    let validate: @Sendable (ServerSchemaState) -> Bool
}

enum ServerMigrationEnvironment: Sendable { case staging, production }
enum ServerMigrationError: Error, Equatable, Sendable {
    case stagingRequired, invalidPlan, validationFailed
}

actor FileBackedServerSchemaStore {
    private let stateURL: URL
    private let backupURL: URL

    init(stateURL: URL) {
        self.stateURL = stateURL
        self.backupURL = stateURL.appendingPathExtension("pre-migration-backup")
    }

    func load() throws -> ServerSchemaState {
        try JSONDecoder().decode(ServerSchemaState.self, from: Data(contentsOf: stateURL))
    }

    func seed(_ state: ServerSchemaState) throws {
        try persist(state, to: stateURL)
    }

    func beginMigrationBackup() throws {
        let data = try Data(contentsOf: stateURL)
        try data.write(to: backupURL, options: [.atomic, .completeFileProtection])
    }

    func commit(_ state: ServerSchemaState) throws {
        try persist(state, to: stateURL)
    }

    func restoreBackup() throws {
        let data = try Data(contentsOf: backupURL)
        try data.write(to: stateURL, options: [.atomic, .completeFileProtection])
    }

    private func persist(_ state: ServerSchemaState, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try JSONEncoder().encode(state).write(to: url, options: [.atomic, .completeFileProtection])
    }
}

struct StagingServerMigrationRunner: Sendable {
    let environment: ServerMigrationEnvironment
    let store: FileBackedServerSchemaStore

    func migrate(to targetVersion: Int, using steps: [ServerMigrationStep]) async throws -> ServerSchemaState {
        guard environment == .staging else { throw ServerMigrationError.stagingRequired }
        var state = try await store.load()
        guard targetVersion >= state.version else { throw ServerMigrationError.invalidPlan }
        try await store.beginMigrationBackup()
        do {
            while state.version < targetVersion {
                guard let step = steps.first(where: {
                    $0.fromVersion == state.version && $0.toVersion == state.version + 1
                }) else { throw ServerMigrationError.invalidPlan }
                var transformed = try step.transform(state)
                transformed.version = step.toVersion
                guard step.validate(transformed) else { throw ServerMigrationError.validationFailed }
                state = transformed
            }
            try await store.commit(state)
            return state
        } catch {
            try await store.restoreBackup()
            throw error
        }
    }
}
