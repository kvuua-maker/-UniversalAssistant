import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Bills receipts and documents")
struct BillsReceiptsDocumentsEngineTests {
    let engine = BillsReceiptsDocumentsEngine()

    private func document(kind: EverydayDocumentKind = .bill, due: DocumentFactConfidence = .verifiedSource) -> EverydayDocument {
        .init(id: "1", kind: kind, title: "Electricity bill", merchant: .init(value: "Energy UA", confidence: .verifiedSource),
              total: .init(value: Money(amount: 1200, currency: "UAH"), confidence: .verifiedSource),
              dueDate: .init(value: Date(timeIntervalSince1970: 2_000), confidence: due),
              purchaseDate: nil, warrantyEnd: nil, source: "scan", sourceObjectID: "scan-1",
              openReference: "document://scan-1", officialPaymentURL: URL(string: "https://pay.example/bill/1"))
    }

    @Test func unverifiedExtractedDueDateCannotCreateReminder() {
        #expect(engine.dueDateReminder(for: document(due: .extractedUnverified)) ==
                .unavailable(reason: "verified_due_date_unavailable"))
    }

    @Test func paymentIsOnlyConfirmedOfficialHTTPSHandoff() {
        #expect(engine.payment(for: document()) ==
                .paymentHandoff(URL(string: "https://pay.example/bill/1")!, requiresConfirmation: true))
    }

    @Test func documentSearchPreservesExactSourceProvenance() {
        let result = engine.personalSearchResult(for: document())
        #expect(result.sourceObjectID == "scan-1")
        #expect(result.openReference == "document://scan-1")
    }

    @Test func warrantyReminderRequiresVerifiedReceiptAssociation() {
        let end = Date(timeIntervalSince1970: 9_000)
        let receipt = EverydayDocument(
            id: "receipt-1", kind: .receipt, title: "Television receipt",
            merchant: nil, total: nil, dueDate: nil,
            purchaseDate: .init(value: Date(timeIntervalSince1970: 1_000), confidence: .verifiedSource),
            warrantyEnd: .init(value: end, confidence: .verifiedSource),
            source: "gmail", sourceObjectID: "message-1", openReference: "gmail://message-1",
            officialPaymentURL: nil
        )
        #expect(engine.warrantyReminder(for: receipt) == .reminder(title: "Television receipt", dueDate: end))
        let unverified = EverydayDocument(
            id: receipt.id, kind: receipt.kind, title: receipt.title,
            merchant: nil, total: nil, dueDate: nil,
            purchaseDate: .init(value: Date(timeIntervalSince1970: 1_000), confidence: .extractedUnverified),
            warrantyEnd: receipt.warrantyEnd, source: receipt.source,
            sourceObjectID: receipt.sourceObjectID, openReference: receipt.openReference,
            officialPaymentURL: nil
        )
        #expect(engine.warrantyReminder(for: unverified) ==
                .unavailable(reason: "verified_warranty_association_unavailable"))
    }

    @Test func billSearchUsesAllRoutedAuthorizedSources() async {
        struct Source: PersonalSearchSource {
            let id: PersonalSearchSourceID
            func search(query: String, limit: Int) async -> PersonalSearchSourceResponse {
                .init(source: id, results: [], isComplete: true, unavailableReason: nil)
            }
        }
        let sources: [any PersonalSearchSource] = [
            Source(id: .local(.files)), Source(id: .connectedEmail("gmail"))
        ]
        let report = await engine.searchAcrossSources(query: "invoice", sources: sources)
        #expect(report.searchedSources == Set(sources.map(\.id)))
    }
}
