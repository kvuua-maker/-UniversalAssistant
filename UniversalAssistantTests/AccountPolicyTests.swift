import Testing
@testable import UniversalAssistant

@Suite("M8 account and authentication decision")
struct AccountPolicyTests {
    @Test func launchIsUsefulBeforeRegistrationButHasAccountModel() {
        #expect(AccountPolicy.launch.accountRequiredEventually)
        #expect(!AccountPolicy.launch.firstScreenRequiresAccount)
        #expect(!AccountPolicy.launch.localFeaturesRequireNetwork)
        #expect(AccountPolicy.launch.primarySignInMethod == .signInWithApple)
    }

    @Test func canonicalGuestAndFreeLimitsAreExplicit() {
        #expect(AccountPolicy.launch.guestActionLimit == 15)
        #expect(AccountPolicy.launch.guestDurationDays == 7)
        #expect(AccountPolicy.launch.freeActionLimit == 30)
        #expect(AccountPolicy.launch.freeCycleDays == 7)
    }

    @Test func logoutRemovesRemoteAuthorityWithoutDestroyingOwnedLocalData() {
        let policy = LogoutPolicy.standard
        #expect(policy.preserveLocalUserOwnedData)
        #expect(policy.unregisterPushToken && policy.cancelAccountScopedJobs && policy.revokeProviderTokens)
    }
}
