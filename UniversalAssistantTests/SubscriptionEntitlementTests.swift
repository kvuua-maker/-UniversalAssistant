import Foundation
import Testing
@testable import UniversalAssistant

@Suite("StoreKit entitlement truth")
struct SubscriptionEntitlementTests {
    @Test func unverifiedTransactionNeverUnlocksPremium() {
        let result = EntitlementResolver().resolve([.init(productID: "premium.monthly", state: .active, expirationDate: .distantFuture, verified: false)])
        #expect(result.level == .free)
        #expect(!result.mayUsePremiumCapabilities)
    }

    @Test func activeAndGracePeriodRemainPremiumWhenUnexpired() {
        for state in [SubscriptionState.active, .gracePeriod] {
            let result = EntitlementResolver().resolve([.init(productID: "premium", state: state, expirationDate: .distantFuture, verified: true)])
            #expect(result.level == .premium)
        }
    }

    @Test func expirationRevocationAndBillingRetryDowngradeGracefully() {
        for state in [SubscriptionState.expired, .revoked, .billingRetry] {
            let result = EntitlementResolver().resolve([.init(productID: "premium", state: state, expirationDate: .distantPast, verified: true)])
            #expect(result.level == .free)
            #expect(result.mayReadOwnedData && result.mayExportOwnedData)
            #expect(!result.mayUsePremiumCapabilities)
        }
    }
}
