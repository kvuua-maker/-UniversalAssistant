import Foundation

enum AppleCredentialState: String, Codable, Sendable { case authorized, revoked, notFound, transferred, unknown }

struct VerifiedAppleIdentity: Equatable, Codable, Sendable {
    let subject: String
    let verifiedAt: Date
}

protocol AppleIdentityTokenVerifier: Sendable {
    func verify(identityToken: Data, authorizationCode: Data) async throws -> VerifiedAppleIdentity
}

protocol AppleCredentialStateProvider: Sendable {
    func credentialState(for subject: String) async -> AppleCredentialState
}

enum AppleAccountSessionState: Equatable, Sendable {
    case signedOut, signedIn(VerifiedAppleIdentity), reauthenticationRequired
}

enum AppleAccountSessionError: Error, Equatable, Sendable { case missingCredential, invalidVerifiedIdentity }

actor AppleAccountSession {
    private let verifier: any AppleIdentityTokenVerifier
    private let credentialProvider: any AppleCredentialStateProvider
    private(set) var state: AppleAccountSessionState = .signedOut

    init(verifier: any AppleIdentityTokenVerifier, credentialProvider: any AppleCredentialStateProvider) {
        self.verifier = verifier
        self.credentialProvider = credentialProvider
    }

    func signIn(identityToken: Data?, authorizationCode: Data?) async throws -> AppleAccountSessionState {
        guard let identityToken, !identityToken.isEmpty, let authorizationCode, !authorizationCode.isEmpty else {
            throw AppleAccountSessionError.missingCredential
        }
        let identity = try await verifier.verify(identityToken: identityToken, authorizationCode: authorizationCode)
        guard !identity.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppleAccountSessionError.invalidVerifiedIdentity
        }
        state = .signedIn(identity)
        return state
    }

    func refreshCredentialState() async -> AppleAccountSessionState {
        guard case .signedIn(let identity) = state else { return state }
        switch await credentialProvider.credentialState(for: identity.subject) {
        case .authorized: return state
        case .revoked, .notFound, .transferred, .unknown:
            state = .reauthenticationRequired
            return state
        }
    }

    func signOut() { state = .signedOut }
}

#if canImport(AuthenticationServices)
import AuthenticationServices

struct SystemAppleCredentialStateProvider: AppleCredentialStateProvider {
    func credentialState(for subject: String) async -> AppleCredentialState {
        await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: subject) { state, _ in
                let mapped: AppleCredentialState = switch state {
                case .authorized: .authorized
                case .revoked: .revoked
                case .notFound: .notFound
                case .transferred: .transferred
                @unknown default: .unknown
                }
                continuation.resume(returning: mapped)
            }
        }
    }
}
#endif
