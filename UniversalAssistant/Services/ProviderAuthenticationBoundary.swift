import Foundation
import Security

enum ProviderAuthorizationMethod: String, Codable, Sendable {
    case publicAccess, oauth, officialAuthenticatedHandoff, unsupported
}

struct ProviderAuthorizationContract: Equatable, Sendable {
    let providerID: String
    let method: ProviderAuthorizationMethod
    var officialSignInURL: URL?
    var requiredScopes: Set<String> = []
}

struct ProviderOAuthCredential: Equatable, Sendable {
    let accessToken: String
    let grantedScopes: Set<String>
    let expiresAt: Date

    var isStructurallyValid: Bool {
        !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

protocol ProviderCredentialStore: Sendable {
    func save(_ credential: ProviderOAuthCredential, providerID: String) async throws
    func load(providerID: String) async throws -> ProviderOAuthCredential?
    func delete(providerID: String) async throws
}

protocol ProviderOAuthRevoking: Sendable {
    func revoke(accessToken: String, contract: ProviderAuthorizationContract) async throws
}

enum ProviderAuthenticationError: Error, Equatable, Sendable {
    case invalidContract
    case oauthRequired
    case invalidCredential
    case insufficientScopes
    case invalidOfficialDestination
}

enum ProviderAccessState: Equatable, Sendable {
    case publicAccess
    case authorized(expiresAt: Date)
    case reauthorizationRequired
    case officialSignInRequired(URL)
    case unavailable
}

actor ProviderAuthenticationBoundary {
    private let store: any ProviderCredentialStore
    private let revoker: (any ProviderOAuthRevoking)?

    init(store: any ProviderCredentialStore, revoker: (any ProviderOAuthRevoking)? = nil) {
        self.store = store
        self.revoker = revoker
    }

    func connect(
        _ credential: ProviderOAuthCredential,
        to contract: ProviderAuthorizationContract,
        now: Date = .now
    ) async throws {
        try validate(contract)
        guard contract.method == .oauth else { throw ProviderAuthenticationError.oauthRequired }
        guard credential.isStructurallyValid, credential.expiresAt > now else {
            throw ProviderAuthenticationError.invalidCredential
        }
        guard credential.grantedScopes.isSuperset(of: contract.requiredScopes) else {
            throw ProviderAuthenticationError.insufficientScopes
        }
        try await store.save(credential, providerID: contract.providerID)
    }

    func accessState(
        for contract: ProviderAuthorizationContract,
        now: Date = .now
    ) async throws -> ProviderAccessState {
        try validate(contract)
        switch contract.method {
        case .publicAccess:
            return .publicAccess
        case .oauth:
            guard let credential = try await store.load(providerID: contract.providerID) else {
                return try officialFallback(contract)
            }
            guard credential.isStructurallyValid, credential.expiresAt > now,
                  credential.grantedScopes.isSuperset(of: contract.requiredScopes) else {
                return .reauthorizationRequired
            }
            return .authorized(expiresAt: credential.expiresAt)
        case .officialAuthenticatedHandoff:
            return try officialFallback(contract)
        case .unsupported:
            return .unavailable
        }
    }

    func disconnect(providerID: String) async throws {
        guard validProviderID(providerID) else { throw ProviderAuthenticationError.invalidContract }
        try await store.delete(providerID: providerID)
    }

    func disconnect(_ contract: ProviderAuthorizationContract) async throws {
        try validate(contract)
        if contract.method == .oauth, let credential = try await store.load(providerID: contract.providerID),
           let revoker {
            try await revoker.revoke(accessToken: credential.accessToken, contract: contract)
        }
        try await store.delete(providerID: contract.providerID)
    }

    private func validate(_ contract: ProviderAuthorizationContract) throws {
        guard validProviderID(contract.providerID),
              !contract.requiredScopes.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { throw ProviderAuthenticationError.invalidContract }
    }

    private func validProviderID(_ providerID: String) -> Bool {
        !providerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func officialFallback(_ contract: ProviderAuthorizationContract) throws -> ProviderAccessState {
        guard let url = contract.officialSignInURL else { return .reauthorizationRequired }
        guard url.scheme?.lowercased() == "https", url.host != nil,
              !url.path.isEmpty, url.path != "/" else {
            throw ProviderAuthenticationError.invalidOfficialDestination
        }
        return .officialSignInRequired(url)
    }
}

final class KeychainProviderCredentialStore: ProviderCredentialStore, @unchecked Sendable {
    private let service: String

    init(service: String = "com.universalassistant.provider-oauth") {
        self.service = service
    }

    func save(_ credential: ProviderOAuthCredential, providerID: String) async throws {
        let data = try JSONEncoder().encode(CodableCredential(credential))
        let query = baseQuery(providerID: providerID)
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else {
            throw KeychainCredentialError.writeFailed
        }
    }

    func load(providerID: String) async throws -> ProviderOAuthCredential? {
        var query = baseQuery(providerID: providerID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainCredentialError.readFailed
        }
        return try JSONDecoder().decode(CodableCredential.self, from: data).credential
    }

    func delete(providerID: String) async throws {
        let status = SecItemDelete(baseQuery(providerID: providerID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainCredentialError.deleteFailed
        }
    }

    private func baseQuery(providerID: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: providerID]
    }

    private struct CodableCredential: Codable {
        let accessToken: String
        let grantedScopes: Set<String>
        let expiresAt: Date

        init(_ credential: ProviderOAuthCredential) {
            accessToken = credential.accessToken
            grantedScopes = credential.grantedScopes
            expiresAt = credential.expiresAt
        }

        var credential: ProviderOAuthCredential {
            .init(accessToken: accessToken, grantedScopes: grantedScopes, expiresAt: expiresAt)
        }
    }

    private enum KeychainCredentialError: Error { case writeFailed, readFailed, deleteFailed }
}
