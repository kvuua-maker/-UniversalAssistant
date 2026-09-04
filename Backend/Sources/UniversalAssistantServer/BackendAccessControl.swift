#if canImport(CryptoKit)
import CryptoKit
#else
@preconcurrency import Crypto
#endif
import Foundation

struct BackendIdentityClaims: Codable, Equatable, Sendable {
    let subjectID: String
    let audience: String
    let expiresAt: Date
    let tenantPartnerID: UUID?
    let role: PartnerPlatformRole
    let permissions: Set<PartnerPlatformPermission>
}

enum BackendAuthenticationError: Error, Equatable, Sendable {
    case missingCredential, malformedCredential, invalidSignature, expired, wrongAudience, invalidClaims
}

struct HMACBearerAuthenticator: Sendable {
    private let key: SymmetricKey
    private let audience: String

    init(runtimeSecret: Data, audience: String) throws {
        guard runtimeSecret.count >= 32, !audience.isEmpty else { throw BackendAuthenticationError.invalidClaims }
        key = SymmetricKey(data: runtimeSecret); self.audience = audience
    }

    func authenticate(authorizationHeader: String?, now: Date = .now) throws -> PartnerPrincipal {
        guard let authorizationHeader, authorizationHeader.hasPrefix("Bearer ") else { throw BackendAuthenticationError.missingCredential }
        let parts = authorizationHeader.dropFirst(7).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, let payload = Data(base64URLEncoded: String(parts[0])),
              let signature = Data(base64URLEncoded: String(parts[1])) else { throw BackendAuthenticationError.malformedCredential }
        guard HMAC<SHA256>.isValidAuthenticationCode(signature, authenticating: payload, using: key) else { throw BackendAuthenticationError.invalidSignature }
        guard let claims = try? JSONDecoder().decode(BackendIdentityClaims.self, from: payload), !claims.subjectID.isEmpty else { throw BackendAuthenticationError.invalidClaims }
        guard claims.audience == audience else { throw BackendAuthenticationError.wrongAudience }
        guard claims.expiresAt > now else { throw BackendAuthenticationError.expired }
        if claims.role != .internalAdmin, claims.tenantPartnerID == nil { throw BackendAuthenticationError.invalidClaims }
        return .init(subjectID: claims.subjectID, tenantPartnerID: claims.tenantPartnerID, role: claims.role, permissions: claims.permissions)
    }

    func issueForTesting(_ claims: BackendIdentityClaims) throws -> String {
        let payload = try JSONEncoder().encode(claims)
        let signature = Data(HMAC<SHA256>.authenticationCode(for: payload, using: key))
        return "Bearer \(payload.base64URLEncodedString()).\(signature.base64URLEncodedString())"
    }
}

actor PrincipalRateLimiter {
    struct Policy: Equatable, Sendable { let maximumRequests: Int; let window: TimeInterval }
    private let policy: Policy
    private var buckets: [String: (start: Date, count: Int)] = [:]

    init(policy: Policy) { self.policy = policy }

    func allow(subjectID: String, now: Date = .now) -> Bool {
        guard !subjectID.isEmpty, policy.maximumRequests > 0, policy.window > 0 else { return false }
        var bucket = buckets[subjectID] ?? (now, 0)
        if now.timeIntervalSince(bucket.start) >= policy.window { bucket = (now, 0) }
        guard bucket.count < policy.maximumRequests else { return false }
        bucket.count += 1; buckets[subjectID] = bucket
        return true
    }
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var text = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        text += String(repeating: "=", count: (4 - text.count % 4) % 4)
        self.init(base64Encoded: text)
    }
    func base64URLEncodedString() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
