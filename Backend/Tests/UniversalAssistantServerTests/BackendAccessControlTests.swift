import Foundation
import Testing
@testable import UniversalAssistantServer

@Suite("Backend authentication and ingress rate limiting")
struct BackendAccessControlTests {
    private let now = Date(timeIntervalSince1970: 10_000)
    private let secret = Data(repeating: 7, count: 32)

    @Test func signedBearerCreatesOnlyVerifiedScopedPrincipal() throws {
        let auth = try HMACBearerAuthenticator(runtimeSecret: secret, audience: "ua-backend")
        let partner = UUID()
        let header = try auth.issueForTesting(.init(subjectID: "operator", audience: "ua-backend", expiresAt: now.addingTimeInterval(60), tenantPartnerID: partner, role: .partnerOperator, permissions: [.viewDashboard]))
        let principal = try auth.authenticate(authorizationHeader: header, now: now)
        #expect(principal.subjectID == "operator"); #expect(principal.tenantPartnerID == partner)
        #expect(principal.permissions == [.viewDashboard])
    }

    @Test func tamperedExpiredWrongAudienceAndMissingCredentialsFailClosed() throws {
        let auth = try HMACBearerAuthenticator(runtimeSecret: secret, audience: "ua-backend")
        let claims = BackendIdentityClaims(subjectID: "admin", audience: "ua-backend", expiresAt: now.addingTimeInterval(1), tenantPartnerID: nil, role: .internalAdmin, permissions: [.reviewPartners])
        let valid = try auth.issueForTesting(claims)
        #expect(throws: BackendAuthenticationError.missingCredential) { try auth.authenticate(authorizationHeader: nil, now: now) }
        #expect(throws: BackendAuthenticationError.invalidSignature) { try auth.authenticate(authorizationHeader: valid + "x", now: now) }
        #expect(throws: BackendAuthenticationError.expired) { try auth.authenticate(authorizationHeader: valid, now: now.addingTimeInterval(2)) }
        let other = try HMACBearerAuthenticator(runtimeSecret: secret, audience: "other")
        #expect(throws: BackendAuthenticationError.wrongAudience) { try other.authenticate(authorizationHeader: valid, now: now) }
    }

    @Test func limiterIsPrincipalScopedBoundedAndResetsOnlyAfterWindow() async {
        let limiter = PrincipalRateLimiter(policy: .init(maximumRequests: 2, window: 60))
        #expect(await limiter.allow(subjectID: "a", now: now)); #expect(await limiter.allow(subjectID: "a", now: now))
        #expect(await !limiter.allow(subjectID: "a", now: now)); #expect(await limiter.allow(subjectID: "b", now: now))
        #expect(await limiter.allow(subjectID: "a", now: now.addingTimeInterval(60)))
    }
}
