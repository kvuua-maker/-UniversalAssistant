import Foundation

enum SubscriptionState: String, Codable, Sendable { case active, gracePeriod, billingRetry, expired, revoked }
enum EntitlementLevel: String, Codable, Sendable { case free, premium }

struct VerifiedSubscription: Equatable, Sendable {
    let productID: String
    let state: SubscriptionState
    let expirationDate: Date?
    let verified: Bool
}

struct EntitlementSnapshot: Equatable, Sendable {
    let level: EntitlementLevel
    let subscriptionState: SubscriptionState?
    let mayUsePremiumCapabilities: Bool
    let mayReadOwnedData: Bool
    let mayExportOwnedData: Bool
}

struct EntitlementResolver: Sendable {
    func resolve(_ subscriptions: [VerifiedSubscription], now: Date = .now) -> EntitlementSnapshot {
        let verified = subscriptions.filter(\.verified)
        let best = verified.sorted { lhs, rhs in
            (lhs.expirationDate ?? .distantFuture) > (rhs.expirationDate ?? .distantFuture)
        }.first { item in
            switch item.state {
            case .active, .gracePeriod: return item.expirationDate.map { $0 > now } ?? true
            case .billingRetry, .expired, .revoked: return false
            }
        }
        if let best {
            return .init(level: .premium, subscriptionState: best.state,
                         mayUsePremiumCapabilities: true, mayReadOwnedData: true, mayExportOwnedData: true)
        }
        let state = verified.first?.state
        return .init(level: .free, subscriptionState: state,
                     mayUsePremiumCapabilities: false, mayReadOwnedData: true, mayExportOwnedData: true)
    }
}

protocol PurchaseRestoring: Sendable { func restore() async throws }

#if canImport(StoreKit)
import StoreKit
struct StoreKitPurchaseRestorer: PurchaseRestoring {
    func restore() async throws { try await AppStore.sync() }
}
#endif
