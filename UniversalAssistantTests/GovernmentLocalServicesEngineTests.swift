import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Government and local services") struct GovernmentLocalServicesEngineTests {
    @Test func catalogUsesOnlyOfficialHTTPSHandoffsAndRequiresConfirmation() throws {
        let engine = GovernmentLocalServicesEngine()
        for item in engine.launchCapabilities() {
            #expect(item.officialURL.scheme == "https")
            #expect(try engine.verifiedHandoff(item, confirmed: false) == nil)
            #expect(try engine.verifiedHandoff(item, confirmed: true) == item.officialURL)
        }
    }

    @Test func unverifiedThirdPartyCannotHandleConsequentialGovernmentAction() {
        let fake = GovernmentServiceCapability(id: "fake", kind: .utility, title: "Fake",
            officialURL: URL(string: "https://payments.example/utility")!,
            accessDepth: .officialPublicHandoff, requiresConfirmation: true)
        #expect(throws: GovernmentServiceError.unverifiedSource) {
            try GovernmentLocalServicesEngine().verifiedHandoff(fake, confirmed: true)
        }
    }

    @Test func privateDiiaDataIsExplicitlyUnavailableWithoutApprovedIntegration() {
        #expect(throws: GovernmentServiceError.privateDataUnavailable) {
            try GovernmentLocalServicesEngine().requestPrivateDiiaDocuments()
        }
    }

    @Test func diiaIntegrationIsNotMisrepresentedAsPublicPrivateDataAccess() throws {
        let integration = try #require(GovernmentLocalServicesEngine().launchCapabilities()
            .first { $0.kind == .diiaIntegration })
        #expect(integration.accessDepth == .partnerApprovalRequired)
    }

    @Test func utilityBillReusesConfirmedPaymentHandoffOnlyForConfiguredOfficialProvider() throws {
        let official = URL(string: "https://utility.city.gov.ua/pay/bill-1")!
        let document = EverydayDocument(id: "bill-1", kind: .bill, title: "Utility",
            merchant: nil, total: nil, dueDate: nil, purchaseDate: nil, warrantyEnd: nil,
            source: "files", sourceObjectID: "file-1", openReference: "file:///bill.pdf",
            officialPaymentURL: official)
        #expect(throws: GovernmentServiceError.unverifiedSource) {
            try GovernmentLocalServicesEngine().officialBillPayment(for: document)
        }
        #expect(try GovernmentLocalServicesEngine(additionalOfficialHosts: ["utility.city.gov.ua"])
            .officialBillPayment(for: document) == .paymentHandoff(official, requiresConfirmation: true))
    }
}
