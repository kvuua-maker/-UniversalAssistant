import XCTest
@testable import UniversalAssistant

final class IntegrationFallbackPolicyTests: XCTestCase {
    private let policy = IntegrationFallbackPolicy()

    func testCanonicalDomainChains() {
        XCTAssertEqual(policy.chain(for: .product), [.directAPI, .structuredFeed, .officialWeb, .phone, .navigation])
        XCTAssertEqual(policy.chain(for: .restaurant), [.directAPI, .officialWeb, .phone, .navigation])
        XCTAssertEqual(policy.chain(for: .ticket), [.directAPI, .authenticatedProvider, .deepLink, .officialApp])
        XCTAssertEqual(policy.chain(for: .service), [.directAPI, .officialWeb, .phone])
        XCTAssertEqual(policy.chain(for: .appAction), [.directAPI, .appIntent, .shortcut, .deepLink, .officialApp])
    }

    func testSelectsFirstAvailableStepWithoutInventingCapability() {
        XCTAssertEqual(
            policy.select(for: .product, available: [.officialWeb, .navigation]),
            IntegrationFallbackSelection(step: .officialWeb, reason: nil)
        )
        XCTAssertNil(policy.select(for: .ticket, available: [.phone]))
    }

    func testFallbackReasonIsPreservedForTruthfulPresentation() {
        XCTAssertEqual(
            policy.select(for: .service, available: [.phone], fallbackReason: .approvalRequired),
            IntegrationFallbackSelection(step: .phone, reason: .approvalRequired)
        )
    }

    func testVerifiedEquivalentOverrideRequiresExplicitReason() {
        XCTAssertEqual(
            policy.select(
                for: .appAction,
                available: [.shortcut, .officialApp],
                fallbackReason: .equivalentUserOutcome,
                verifiedEquivalentOverride: .officialApp
            ),
            IntegrationFallbackSelection(step: .officialApp, reason: .equivalentUserOutcome)
        )
        XCTAssertEqual(
            policy.select(for: .appAction, available: [.shortcut, .officialApp], verifiedEquivalentOverride: .officialApp),
            IntegrationFallbackSelection(step: .shortcut, reason: nil)
        )
    }
}
