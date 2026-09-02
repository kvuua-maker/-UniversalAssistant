import Foundation
import Testing
@testable import UniversalAssistant

private struct AppleVerifierFixture: AppleIdentityTokenVerifier {
    let identity: VerifiedAppleIdentity
    func verify(identityToken: Data, authorizationCode: Data) -> VerifiedAppleIdentity { identity }
}
private struct AppleStateFixture: AppleCredentialStateProvider {
    let state: AppleCredentialState
    func credentialState(for subject: String) -> AppleCredentialState { state }
}

@Suite("Sign in with Apple session boundary")
struct AppleAccountSessionTests {
    @Test func missingCredentialNeverCreatesSession() async throws {
        let session = AppleAccountSession(verifier: AppleVerifierFixture(identity: .init(subject: "user", verifiedAt: .now)), credentialProvider: AppleStateFixture(state: .authorized))
        await #expect(throws: AppleAccountSessionError.missingCredential) { try await session.signIn(identityToken: nil, authorizationCode: nil) }
    }

    @Test func onlyVerifierOutputCreatesSignedInState() async throws {
        let identity = VerifiedAppleIdentity(subject: "apple-subject", verifiedAt: .now)
        let session = AppleAccountSession(verifier: AppleVerifierFixture(identity: identity), credentialProvider: AppleStateFixture(state: .authorized))
        #expect(try await session.signIn(identityToken: Data([1]), authorizationCode: Data([2])) == .signedIn(identity))
    }

    @Test func revokedCredentialRequiresReauthentication() async throws {
        let identity = VerifiedAppleIdentity(subject: "apple-subject", verifiedAt: .now)
        let session = AppleAccountSession(verifier: AppleVerifierFixture(identity: identity), credentialProvider: AppleStateFixture(state: .revoked))
        _ = try await session.signIn(identityToken: Data([1]), authorizationCode: Data([2]))
        #expect(await session.refreshCredentialState() == .reauthenticationRequired)
    }
}
