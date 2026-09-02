import Foundation
import Testing
@testable import UniversalAssistantServer

private func riskInput(duplicate: Bool = false, reference: String? = nil,
                       conversions: Int = 1, refunds: Int = 0,
                       gross: Decimal = 100, commission: Decimal = 10) -> PartnerRiskInput {
    .init(partnerID: UUID(), attributionID: UUID(), externalTransactionID: "tx",
          pseudonymousReference: reference, partnerControlledReferences: ["partner-user"],
          recentConversionCount: conversions, recentRefundCount: refunds,
          grossAmount: gross, commissionAmount: commission,
          duplicateAttribution: duplicate, duplicateExternalTransaction: false, webhookReplay: false)
}

@Suite("Partner fraud and abuse controls")
struct PartnerFraudControlsTests {
    @Test func duplicatesAreIdempotentlyRejectedAndAudited() async {
        let engine = PartnerFraudControlEngine(policy: .init(version: "v1", maximumConversionsPerWindow: 20, refundReviewRatio: 0.5))
        let result = await engine.assess(riskInput(duplicate: true))
        #expect(result.disposition == .rejectDuplicate)
        #expect(result.signals == [.duplicateAttribution])
        #expect(await engine.auditTrail().first?.policyVersion == "v1")
    }

    @Test func suspiciousPatternsRequireReviewWithoutAutomaticGuilt() async {
        let engine = PartnerFraudControlEngine(policy: .init(version: "v2", maximumConversionsPerWindow: 10, refundReviewRatio: 0.4))
        let result = await engine.assess(riskInput(reference: "partner-user", conversions: 12, refunds: 6,
                                                   gross: 10, commission: 11))
        #expect(result.disposition == .reviewRequired)
        #expect(result.signals == [.suspectedSelfReferral, .excessiveConversionVelocity,
                                   .excessiveRefundRatio, .commissionExceedsGross])
    }

    @Test func normalVerifiedPatternIsAllowedExplainably() async {
        let engine = PartnerFraudControlEngine(policy: .init(version: "v1", maximumConversionsPerWindow: 20, refundReviewRatio: 0.5))
        let result = await engine.assess(riskInput())
        #expect(result == .init(signals: [], disposition: .allow))
        #expect(await engine.auditTrail().count == 1)
    }
}
