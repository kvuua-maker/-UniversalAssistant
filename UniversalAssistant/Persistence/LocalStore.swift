import Foundation

actor LocalStore {
    static let shared = LocalStore()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let baseDirectory: URL?

    init(baseDirectory: URL? = nil) {
        self.baseDirectory = baseDirectory
    }

    func save<T: Encodable>(_ value: T, as name: String) throws {
        try encoder.encode(value).write(to: try url(for: name), options: .atomic)
    }

    func load<T: Decodable>(_ type: T.Type, from name: String) throws -> T? {
        let fileURL = try url(for: name)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try decoder.decode(type, from: Data(contentsOf: fileURL))
    }

    func saveVersioned<T: Encodable>(_ value: T, schemaVersion: Int, as name: String) throws {
        guard schemaVersion > 0 else { throw LocalStoreVersionError.invalidVersion }
        let envelope = VersionedLocalRecord(schemaVersion: schemaVersion, payload: try encoder.encode(value))
        try encoder.encode(envelope).write(to: try url(for: name), options: .atomic)
    }

    func loadVersioned<T: Codable & Sendable>(
        _ type: T.Type,
        currentVersion: Int,
        from name: String,
        migrate: @Sendable (Int, Data) throws -> T
    ) throws -> VersionedLoadResult<T> {
        guard currentVersion > 0 else { throw LocalStoreVersionError.invalidVersion }
        let fileURL = try url(for: name)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .missing }
        do {
            let envelope = try decoder.decode(VersionedLocalRecord.self, from: Data(contentsOf: fileURL))
            guard envelope.schemaVersion <= currentVersion else { throw LocalStoreVersionError.futureVersion }
            if envelope.schemaVersion == currentVersion {
                return .loaded(try decoder.decode(type, from: envelope.payload))
            }
            let migrated = try migrate(envelope.schemaVersion, envelope.payload)
            try saveVersioned(migrated, schemaVersion: currentVersion, as: name)
            return .migrated(migrated, fromVersion: envelope.schemaVersion)
        } catch LocalStoreVersionError.futureVersion {
            throw LocalStoreVersionError.futureVersion
        } catch {
            let quarantineURL = fileURL.appendingPathExtension("corrupt-\(UUID().uuidString)")
            try FileManager.default.moveItem(at: fileURL, to: quarantineURL)
            return .quarantinedCorruption(quarantineURL)
        }
    }

    private func url(for name: String) throws -> URL {
        let directory = if let baseDirectory { baseDirectory } else {
            try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appending(path: "UniversalAssistant", directoryHint: .isDirectory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: name)
    }
}

private struct VersionedLocalRecord: Codable { let schemaVersion: Int; let payload: Data }
enum LocalStoreVersionError: Error, Equatable { case invalidVersion, futureVersion }
enum VersionedLoadResult<T: Sendable>: Sendable {
    case missing
    case loaded(T)
    case migrated(T, fromVersion: Int)
    case quarantinedCorruption(URL)
}
