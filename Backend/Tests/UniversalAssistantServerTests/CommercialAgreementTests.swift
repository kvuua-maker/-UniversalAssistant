import Foundation
import Testing
@testable import UniversalAssistantServer

private func agreement(
    id: UUID, partner: UUID, version: Int, from: Date, until: Date?,
    model: CommercialModel, value: Decimal
) -> CommercialAgreementVersion {
    .init(agreementID: id, partnerID: partner, version: version,
          effectiveFrom: from, effectiveUntil: until,
          terms: .init(model: model, rateOrValue: value, currencyCode: "USD",
                       qualifyingEvent: "confirmed", attributionWindowSeconds: 86_400,
                       refundPolicyReference: "refund-v1", settlementPolicyReference: "settlement-v1",
                       geographyCodes: ["US"], scopeReferences: ["all"], floor: nil, cap: nil),
          status: .active, recordedAt: from)
}

@Suite("Versioned commercial agreements")
struct CommercialAgreementTests {
    @Test func qualifyingEventUsesHistoricalVersionWithoutRewrite() async throws {
        let registry = CommercialAgreementRegistry()
        let id = UUID(), partner = UUID(), start = Date(timeIntervalSince1970: 1_000)
        let v1 = agreement(id: id, partner: partner, version: 1, from: start,
                           until: start.addingTimeInterval(100), model: .percentOfConfirmedSale, value: 5)
        let v2 = agreement(id: id, partner: partner, version: 2, from: start.addingTimeInterval(100),
                           until: nil, model: .fixedPerConfirmedOrder, value: 2)
        try await registry.append(v1); try await registry.append(v2)
        #expect(try await registry.applicable(agreementID: id, qualifyingEventAt: start.addingTimeInterval(50)) == v1)
        #expect(try await registry.applicable(agreementID: id, qualifyingEventAt: start.addingTimeInterval(150)) == v2)
        #expect(await registry.history(agreementID: id) == [v1, v2])
    }

    @Test func duplicateOrOverlappingVersionsCannotRewriteHistory() async throws {
        let registry = CommercialAgreementRegistry()
        let id = UUID(), partner = UUID(), start = Date(timeIntervalSince1970: 1_000)
        let v1 = agreement(id: id, partner: partner, version: 1, from: start,
                           until: start.addingTimeInterval(100), model: .percentOfConfirmedSale, value: 5)
        try await registry.append(v1)
        await #expect(throws: CommercialAgreementError.duplicateVersion) { try await registry.append(v1) }
        await #expect(throws: CommercialAgreementError.overlappingEffectivePeriod) {
            try await registry.append(agreement(id: id, partner: partner, version: 2,
                                                from: start.addingTimeInterval(50), until: nil,
                                                model: .customContract, value: 1))
        }
    }

    @Test func allCanonicalModelsAreConfigurationValues() {
        #expect(CommercialModel.allCases.count == 11)
        #expect(CommercialModel(rawValue: "SPONSORED_PLACEMENT") == .sponsoredPlacement)
        #expect(CommercialModel(rawValue: "CUSTOM_CONTRACT") == .customContract)
    }
}
