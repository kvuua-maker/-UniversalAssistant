import Foundation

enum UniversalAccountState: String, Codable, Sendable { case guest, registeredFree, premium }
enum PrimarySignInMethod: String, Codable, Sendable { case signInWithApple }

struct AccountPolicy: Equatable, Sendable {
    let accountRequiredEventually: Bool
    let firstScreenRequiresAccount: Bool
    let primarySignInMethod: PrimarySignInMethod
    let guestActionLimit: Int
    let guestDurationDays: Int
    let freeActionLimit: Int
    let freeCycleDays: Int
    let localFeaturesRequireNetwork: Bool

    static let launch = AccountPolicy(accountRequiredEventually: true,
        firstScreenRequiresAccount: false, primarySignInMethod: .signInWithApple,
        guestActionLimit: 15, guestDurationDays: 7, freeActionLimit: 30,
        freeCycleDays: 7, localFeaturesRequireNetwork: false)
}

enum LocalAccountMergeRule: String, Sendable { case preserveAndDeduplicateByStableIdentifier }

struct LogoutPolicy: Equatable, Sendable {
    let preserveLocalUserOwnedData: Bool
    let unregisterPushToken: Bool
    let cancelAccountScopedJobs: Bool
    let revokeProviderTokens: Bool
    static let standard = Self(preserveLocalUserOwnedData: true, unregisterPushToken: true,
                               cancelAccountScopedJobs: true, revokeProviderTokens: true)
}
