import Foundation

enum IntegrationFallbackDomain: String, CaseIterable, Sendable {
    case product
    case restaurant
    case ticket
    case service
    case appAction
}

enum IntegrationFallbackStep: String, CaseIterable, Sendable {
    case directAPI
    case structuredFeed
    case authenticatedProvider
    case appIntent
    case shortcut
    case deepLink
    case officialApp
    case officialWeb
    case phone
    case navigation
}

enum IntegrationFallbackReason: String, Sendable {
    case unavailable
    case unsupported
    case restricted
    case credentialRequired
    case approvalRequired
    case prohibited
    case inaccessible
    case equivalentUserOutcome
}

struct IntegrationFallbackSelection: Equatable, Sendable {
    let step: IntegrationFallbackStep
    let reason: IntegrationFallbackReason?
}

/// A typed statement of the canonical integration fallback order. Domain engines remain
/// responsible for executing the selected capability and for validating provider facts.
struct IntegrationFallbackPolicy: Sendable {
    func chain(for domain: IntegrationFallbackDomain) -> [IntegrationFallbackStep] {
        switch domain {
        case .product:
            return [.directAPI, .structuredFeed, .officialWeb, .phone, .navigation]
        case .restaurant:
            return [.directAPI, .officialWeb, .phone, .navigation]
        case .ticket:
            return [.directAPI, .authenticatedProvider, .deepLink, .officialApp]
        case .service:
            return [.directAPI, .officialWeb, .phone]
        case .appAction:
            return [.directAPI, .appIntent, .shortcut, .deepLink, .officialApp]
        }
    }

    func select(
        for domain: IntegrationFallbackDomain,
        available: Set<IntegrationFallbackStep>,
        fallbackReason: IntegrationFallbackReason? = nil,
        verifiedEquivalentOverride: IntegrationFallbackStep? = nil
    ) -> IntegrationFallbackSelection? {
        if let override = verifiedEquivalentOverride,
           available.contains(override),
           fallbackReason == .equivalentUserOutcome {
            return IntegrationFallbackSelection(step: override, reason: fallbackReason)
        }

        guard let selected = chain(for: domain).first(where: available.contains) else {
            return nil
        }
        return IntegrationFallbackSelection(step: selected, reason: fallbackReason)
    }
}
