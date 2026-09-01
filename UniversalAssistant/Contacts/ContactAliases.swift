import Foundation

struct ContactAlias: Equatable, Codable, Sendable {
    let normalizedAlias: String
    let contactIdentifier: String
    let confirmedAt: Date
}

protocol ContactAliasPersisting: Sendable {
    func load() async throws -> [ContactAlias]
    func save(_ aliases: [ContactAlias]) async throws
}

actor LocalContactAliasPersistence: ContactAliasPersisting {
    private let store: LocalStore
    init(store: LocalStore = .shared) { self.store = store }
    func load() async throws -> [ContactAlias] {
        try await store.load([ContactAlias].self, from: "contact-aliases.json") ?? []
    }
    func save(_ aliases: [ContactAlias]) async throws {
        try await store.save(aliases, as: "contact-aliases.json")
    }
}

enum ContactAliasError: Error, Equatable {
    case invalidAlias
    case invalidContactIdentifier
}

actor ContactAliasDirectory {
    private let persistence: any ContactAliasPersisting
    private var aliases: [String: ContactAlias] = [:]

    init(persistence: any ContactAliasPersisting = LocalContactAliasPersistence()) {
        self.persistence = persistence
    }

    func restore() async throws {
        aliases = Dictionary(uniqueKeysWithValues: try await persistence.load().map { ($0.normalizedAlias, $0) })
    }

    func confirm(alias: String, forExactContactIdentifier identifier: String, at date: Date = .now) async throws {
        let key = Self.normalize(alias)
        guard !key.isEmpty else { throw ContactAliasError.invalidAlias }
        guard !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ContactAliasError.invalidContactIdentifier
        }
        aliases[key] = ContactAlias(normalizedAlias: key, contactIdentifier: identifier, confirmedAt: date)
        try await persistence.save(aliases.values.sorted { $0.normalizedAlias < $1.normalizedAlias })
    }

    func exactIdentifier(for alias: String) -> String? {
        aliases[Self.normalize(alias)]?.contactIdentifier
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}
