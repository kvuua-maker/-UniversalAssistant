import Foundation
import Testing
@testable import UniversalAssistant

private actor CredentialMemoryStore: ProviderCredentialStore {
    private var credentials: [String: ProviderOAuthCredential] = [:]
    func save(_ credential: ProviderOAuthCredential, providerID: String) { credentials[providerID] = credential }
    func load(providerID: String) -> ProviderOAuthCredential? { credentials[providerID] }
    func delete(providerID: String) { credentials[providerID] = nil }
}

private actor OAuthRevokerSpy: ProviderOAuthRevoking {
    private(set) var providers: [String] = []
    func revoke(accessToken: String, contract: ProviderAuthorizationContract) throws {
        #expect(!accessToken.isEmpty)
        providers.append(contract.providerID)
    }
}

@Suite("Provider authentication boundary") struct ProviderAuthenticationBoundaryTests {
    @Test func localFirstPublicCapabilityRequiresNoAccount() async throws {
        let boundary = ProviderAuthenticationBoundary(store: CredentialMemoryStore())
        let state = try await boundary.accessState(for: .init(providerID: "public", method: .publicAccess))
        #expect(state == .publicAccess)
    }

    @Test func oauthRequiresValidScopedUnexpiredToken() async throws {
        let now = Date(), boundary = ProviderAuthenticationBoundary(store: CredentialMemoryStore())
        let contract = ProviderAuthorizationContract(providerID: "rail", method: .oauth,
            officialSignInURL: URL(string: "https://rail.example/oauth/authorize"), requiredScopes: ["availability"])
        await #expect(throws: ProviderAuthenticationError.insufficientScopes) {
            try await boundary.connect(.init(accessToken: "token", grantedScopes: [],
                                             expiresAt: now.addingTimeInterval(600)), to: contract, now: now)
        }
        try await boundary.connect(.init(accessToken: "token", grantedScopes: ["availability"],
                                         expiresAt: now.addingTimeInterval(600)), to: contract, now: now)
        #expect(try await boundary.accessState(for: contract, now: now) ==
                .authorized(expiresAt: now.addingTimeInterval(600)))
    }

    @Test func missingCredentialUsesExactOfficialSignInHandoff() async throws {
        let boundary = ProviderAuthenticationBoundary(store: CredentialMemoryStore())
        let url = URL(string: "https://hotel.example/account/sign-in")!
        let state = try await boundary.accessState(for: .init(providerID: "hotel", method: .oauth,
                                                               officialSignInURL: url))
        #expect(state == .officialSignInRequired(url))
    }

    @Test func expiredCredentialNeverAuthorizesAndDisconnectDeletesIt() async throws {
        let now = Date(), store = CredentialMemoryStore()
        let boundary = ProviderAuthenticationBoundary(store: store)
        let contract = ProviderAuthorizationContract(providerID: "bus", method: .oauth)
        try await store.save(.init(accessToken: "expired", grantedScopes: [],
                                   expiresAt: now.addingTimeInterval(-1)), providerID: "bus")
        #expect(try await boundary.accessState(for: contract, now: now) == .reauthorizationRequired)
        try await boundary.disconnect(providerID: "bus")
        #expect(try await store.load(providerID: "bus") == nil)
    }

    @Test func homepageIsNotAcceptedAsAuthenticationDestination() async throws {
        let boundary = ProviderAuthenticationBoundary(store: CredentialMemoryStore())
        await #expect(throws: ProviderAuthenticationError.invalidOfficialDestination) {
            try await boundary.accessState(for: .init(providerID: "bad", method: .officialAuthenticatedHandoff,
                                                       officialSignInURL: URL(string: "https://example.com/")))
        }
    }

    @Test func disconnectRevokesProviderBeforeDeletingLocalCredential() async throws {
        let now = Date(), store = CredentialMemoryStore(), revoker = OAuthRevokerSpy()
        let contract = ProviderAuthorizationContract(providerID: "calendar-provider", method: .oauth,
            officialSignInURL: URL(string: "https://provider.example/oauth/revoke"), requiredScopes: ["calendar"])
        try await store.save(.init(accessToken: "secret-token", grantedScopes: ["calendar"],
                                   expiresAt: now.addingTimeInterval(600)), providerID: contract.providerID)
        let boundary = ProviderAuthenticationBoundary(store: store, revoker: revoker)
        try await boundary.disconnect(contract)
        #expect(await revoker.providers == [contract.providerID])
        #expect(try await store.load(providerID: contract.providerID) == nil)
    }
}
