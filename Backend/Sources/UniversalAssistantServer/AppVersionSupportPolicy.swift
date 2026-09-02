import Foundation

struct SemanticAppVersion: Codable, Comparable, Equatable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init(_ value: String) throws {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count),
              let major = Int(parts[0]), let minor = Int(parts[1]) else {
            throw AppVersionPolicyError.invalidVersion
        }
        let parsedPatch = parts.count == 3 ? Int(parts[2]) : 0
        guard let patch = parsedPatch, major >= 0, minor >= 0, patch >= 0 else {
            throw AppVersionPolicyError.invalidVersion
        }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

enum ForcedUpdateReason: String, Codable, Sendable {
    case criticalCompatibility
    case security
    case legal
}

enum AppVersionDisposition: Equatable, Sendable {
    case supported
    case updateAvailable(current: SemanticAppVersion)
    case updateRequired(minimum: SemanticAppVersion, reason: ForcedUpdateReason)
}

enum AppVersionPolicyError: Error, Equatable, Sendable {
    case invalidVersion
    case invalidPolicy
    case unjustifiedForcedUpdate
}

struct AppVersionSupportPolicy: Equatable, Sendable {
    let current: SemanticAppVersion
    let minimumSupported: SemanticAppVersion
    let supportedPriorMinorVersions: Int
    let forcedUpdateReason: ForcedUpdateReason?

    init(
        current: SemanticAppVersion,
        minimumSupported: SemanticAppVersion,
        supportedPriorMinorVersions: Int = 2,
        forcedUpdateReason: ForcedUpdateReason? = nil
    ) throws {
        guard supportedPriorMinorVersions >= 0, minimumSupported <= current else {
            throw AppVersionPolicyError.invalidPolicy
        }
        if minimumSupported < current, forcedUpdateReason == nil {
            throw AppVersionPolicyError.unjustifiedForcedUpdate
        }
        self.current = current
        self.minimumSupported = minimumSupported
        self.supportedPriorMinorVersions = supportedPriorMinorVersions
        self.forcedUpdateReason = forcedUpdateReason
    }

    func evaluate(_ installed: SemanticAppVersion) -> AppVersionDisposition {
        if installed < minimumSupported, let forcedUpdateReason {
            return .updateRequired(minimum: minimumSupported, reason: forcedUpdateReason)
        }
        if installed < current { return .updateAvailable(current: current) }
        return .supported
    }
}
