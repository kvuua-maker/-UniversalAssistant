import Foundation
import Testing
@testable import UniversalAssistant

private actor HubCredentialStore: ProviderCredentialStore {
    var values: [String: ProviderOAuthCredential] = [:]
    func save(_ credential: ProviderOAuthCredential, providerID: String) { values[providerID] = credential }
    func load(providerID: String) -> ProviderOAuthCredential? { values[providerID] }
    func delete(providerID: String) { values.removeValue(forKey: providerID) }
}

private actor HubRevoker: ProviderOAuthRevoking {
    var revoked: [String] = []
    func revoke(accessToken: String, contract: ProviderAuthorizationContract) { revoked.append(contract.providerID) }
}

private actor HubMetadataStore: ConnectedAccountPersisting {
    var values: [ConnectedAccountRecord] = []
    func load() -> [ConnectedAccountRecord] { values }
    func save(_ records: [ConnectedAccountRecord]) { values = records }
}

@Suite("Connected Accounts Hub") struct ConnectedAccountsHubTests {
    private let now = Date(timeIntervalSince1970: 100)

    @Test func connectsWithExactMinimumScopesAndTracksExpiry() async throws {
        let store = HubCredentialStore(), boundary = ProviderAuthenticationBoundary(store: store)
        let contract = ProviderAuthorizationContract(providerID: "gmail", method: .oauth,
            officialSignInURL: URL(string: "https://accounts.google.com/o/oauth2/v2/auth"), requiredScopes: ["gmail.readonly"])
        let hub = ConnectedAccountsHub(authentication: boundary, contracts: [contract], persistence: HubMetadataStore())
        try await hub.connect(providerID: "gmail", displayName: "Gmail", enabledCapabilities: ["search"],
            credential: .init(accessToken: "secret", grantedScopes: ["gmail.readonly"], expiresAt: now.addingTimeInterval(60)), now: now)
        #expect(await hub.snapshot().first?.health == .connected(expiresAt: now.addingTimeInterval(60)))
        #expect(await hub.refresh(now: now.addingTimeInterval(61)).first?.health == .reauthorizationRequired)
    }

    @Test func rejectsExcessScopesInsteadOfSilentlyOverRequesting() async {
        let boundary = ProviderAuthenticationBoundary(store: HubCredentialStore())
        let contract = ProviderAuthorizationContract(providerID: "mail", method: .oauth,
            officialSignInURL: nil, requiredScopes: ["read"])
        let hub = ConnectedAccountsHub(authentication: boundary, contracts: [contract], persistence: HubMetadataStore())
        await #expect(throws: ConnectedAccountsHubError.excessiveScopes) {
            try await hub.connect(providerID: "mail", displayName: "Mail", enabledCapabilities: ["search"],
                credential: .init(accessToken: "x", grantedScopes: ["read", "send"], expiresAt: now.addingTimeInterval(60)), now: now)
        }
    }

    @Test func disconnectRevokesThenDeletesWithoutAffectingOtherAccount() async throws {
        let store = HubCredentialStore(), revoker = HubRevoker()
        let boundary = ProviderAuthenticationBoundary(store: store, revoker: revoker)
        let contracts = ["a", "b"].map { ProviderAuthorizationContract(providerID: $0, method: .oauth,
            officialSignInURL: nil, requiredScopes: ["read"]) }
        let hub = ConnectedAccountsHub(authentication: boundary, contracts: contracts, persistence: HubMetadataStore())
        for id in ["a", "b"] { try await hub.connect(providerID: id, displayName: id, enabledCapabilities: ["search"], credential: .init(accessToken: id, grantedScopes: ["read"], expiresAt: now.addingTimeInterval(60)), now: now) }
        try await hub.disconnect(providerID: "a", now: now)
        #expect(await revoker.revoked == ["a"])
        #expect(await hub.snapshot().map(\.providerID) == ["b"])
        #expect(await store.load(providerID: "b") != nil)
    }

    @Test func restoresOnlyKnownProviderMetadataAfterRestart() async throws {
        let metadata = HubMetadataStore()
        await metadata.save([
            .init(providerID: "known", displayName: "Known", enabledCapabilities: ["search"], requestedScopes: ["read"], health: .reauthorizationRequired, lastCheckedAt: now),
            .init(providerID: "removed", displayName: "Removed", enabledCapabilities: [], requestedScopes: [], health: .unavailable, lastCheckedAt: now)
        ])
        let contract = ProviderAuthorizationContract(providerID: "known", method: .oauth, officialSignInURL: nil, requiredScopes: ["read"])
        let hub = ConnectedAccountsHub(authentication: ProviderAuthenticationBoundary(store: HubCredentialStore()), contracts: [contract], persistence: metadata)
        try await hub.restore()
        #expect(await hub.snapshot().map(\.providerID) == ["known"])
    }
}
