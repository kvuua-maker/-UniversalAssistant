import Foundation

enum ConnectedAccountHealth: Equatable, Codable, Sendable {
    case connected(expiresAt: Date)
    case signInRequired(URL?)
    case reauthorizationRequired
    case unavailable
    case providerError(code: String)
}

struct ConnectedAccountRecord: Equatable, Codable, Sendable {
    let providerID: String
    let displayName: String
    let enabledCapabilities: Set<String>
    let requestedScopes: Set<String>
    var health: ConnectedAccountHealth
    var lastCheckedAt: Date
}

enum ConnectedAccountsHubError: Error, Equatable { case unknownProvider, excessiveScopes }

protocol ConnectedAccountPersisting: Sendable {
    func load() async throws -> [ConnectedAccountRecord]
    func save(_ records: [ConnectedAccountRecord]) async throws
}

actor LocalConnectedAccountPersistence: ConnectedAccountPersisting {
    private let store: LocalStore
    init(store: LocalStore = .shared) { self.store = store }
    func load() async throws -> [ConnectedAccountRecord] {
        try await store.load([ConnectedAccountRecord].self, from: "connected-accounts.json") ?? []
    }
    func save(_ records: [ConnectedAccountRecord]) async throws {
        try await store.save(records, as: "connected-accounts.json")
    }
}

actor ConnectedAccountsHub {
    private let authentication: ProviderAuthenticationBoundary
    private let contracts: [String: ProviderAuthorizationContract]
    private let persistence: any ConnectedAccountPersisting
    private var records: [String: ConnectedAccountRecord] = [:]

    init(authentication: ProviderAuthenticationBoundary, contracts: [ProviderAuthorizationContract],
         persistence: any ConnectedAccountPersisting = LocalConnectedAccountPersistence()) {
        self.authentication = authentication
        self.contracts = Dictionary(uniqueKeysWithValues: contracts.map { ($0.providerID, $0) })
        self.persistence = persistence
    }

    func restore() async throws {
        records = Dictionary(uniqueKeysWithValues: try await persistence.load()
            .filter { contracts[$0.providerID] != nil }.map { ($0.providerID, $0) })
    }

    func connect(providerID: String, displayName: String, enabledCapabilities: Set<String>,
                 credential: ProviderOAuthCredential, now: Date = .now) async throws {
        guard let contract = contracts[providerID] else { throw ConnectedAccountsHubError.unknownProvider }
        guard credential.grantedScopes == contract.requiredScopes else { throw ConnectedAccountsHubError.excessiveScopes }
        try await authentication.connect(credential, to: contract, now: now)
        records[providerID] = .init(providerID: providerID, displayName: displayName,
            enabledCapabilities: enabledCapabilities, requestedScopes: contract.requiredScopes,
            health: .connected(expiresAt: credential.expiresAt), lastCheckedAt: now)
        try await persistence.save(snapshot())
    }

    func refresh(now: Date = .now) async -> [ConnectedAccountRecord] {
        for (providerID, contract) in contracts {
            do {
                let access = try await authentication.accessState(for: contract, now: now)
                let health: ConnectedAccountHealth = switch access {
                case let .authorized(expiresAt): .connected(expiresAt: expiresAt)
                case let .officialSignInRequired(url): .signInRequired(url)
                case .reauthorizationRequired: .reauthorizationRequired
                case .publicAccess: .unavailable
                case .unavailable: .unavailable
                }
                if var record = records[providerID] { record.health = health; record.lastCheckedAt = now; records[providerID] = record }
            } catch {
                if var record = records[providerID] {
                    record.health = .providerError(code: String(describing: type(of: error)))
                    record.lastCheckedAt = now; records[providerID] = record
                }
            }
        }
        try? await persistence.save(snapshot())
        return snapshot()
    }

    func disconnect(providerID: String, now: Date = .now) async throws {
        guard let contract = contracts[providerID] else { throw ConnectedAccountsHubError.unknownProvider }
        try await authentication.disconnect(contract)
        records.removeValue(forKey: providerID)
        try await persistence.save(snapshot())
    }

    func snapshot() -> [ConnectedAccountRecord] { records.values.sorted { $0.providerID < $1.providerID } }
}
