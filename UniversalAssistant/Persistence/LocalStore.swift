import Foundation

actor LocalStore {
    static let shared = LocalStore()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func save<T: Encodable>(_ value: T, as name: String) throws {
        try encoder.encode(value).write(to: try url(for: name), options: .atomic)
    }

    func load<T: Decodable>(_ type: T.Type, from name: String) throws -> T? {
        let fileURL = try url(for: name)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try decoder.decode(type, from: Data(contentsOf: fileURL))
    }

    private func url(for name: String) throws -> URL {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appending(path: "UniversalAssistant", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: name)
    }
}
