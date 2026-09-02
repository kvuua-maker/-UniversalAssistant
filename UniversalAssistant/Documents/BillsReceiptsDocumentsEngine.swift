import Foundation

enum EverydayDocumentKind: String, Codable, Sendable { case bill, receipt, invoice, warranty, ticket, other }
enum DocumentFactConfidence: String, Codable, Sendable { case verifiedSource, extractedUnverified }

struct DocumentFact<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    let value: Value
    let confidence: DocumentFactConfidence
}

struct EverydayDocument: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let kind: EverydayDocumentKind
    let title: String
    let merchant: DocumentFact<String>?
    let total: DocumentFact<Money>?
    let dueDate: DocumentFact<Date>?
    let purchaseDate: DocumentFact<Date>?
    let warrantyEnd: DocumentFact<Date>?
    let source: String
    let sourceObjectID: String
    let openReference: String
    let officialPaymentURL: URL?
}

enum DocumentActionPlan: Equatable, Sendable {
    case reminder(title: String, dueDate: Date)
    case paymentHandoff(URL, requiresConfirmation: Bool)
    case unavailable(reason: String)
}

struct BillsReceiptsDocumentsEngine: Sendable {
    func searchAcrossSources(
        query: String,
        sources: [any PersonalSearchSource]
    ) async -> UniversalPersonalSearchReport {
        await UniversalPersonalSearchEngine(sources: sources).search(query)
    }

    func search(query: String, documents: [EverydayDocument]) -> [EverydayDocument] {
        let terms = query.lowercased().split(separator: " ").map(String.init)
        return documents.filter { document in
            let searchable = [document.title, document.merchant?.value ?? "", document.kind.rawValue]
                .joined(separator: " ").lowercased()
            return terms.allSatisfy(searchable.contains)
        }.sorted { $0.id < $1.id }
    }

    func dueDateReminder(for document: EverydayDocument) -> DocumentActionPlan {
        guard let fact = document.dueDate, fact.confidence == .verifiedSource else {
            return .unavailable(reason: "verified_due_date_unavailable")
        }
        return .reminder(title: document.title, dueDate: fact.value)
    }

    func warrantyReminder(for document: EverydayDocument) -> DocumentActionPlan {
        guard document.kind == .receipt,
              document.purchaseDate?.confidence == .verifiedSource,
              let warranty = document.warrantyEnd, warranty.confidence == .verifiedSource else {
            return .unavailable(reason: "verified_warranty_association_unavailable")
        }
        return .reminder(title: document.title, dueDate: warranty.value)
    }

    func payment(for document: EverydayDocument) -> DocumentActionPlan {
        guard document.kind == .bill || document.kind == .invoice,
              let url = document.officialPaymentURL,
              url.scheme == "https", url.host != nil else {
            return .unavailable(reason: "official_payment_handoff_unavailable")
        }
        return .paymentHandoff(url, requiresConfirmation: true)
    }

    func personalSearchResult(for document: EverydayDocument) -> PersonalSearchResult {
        .init(id: "document:" + document.id, title: document.title,
              subtitle: document.merchant?.value, source: .local(.files),
              sourceObjectID: document.sourceObjectID, openReference: document.openReference,
              freshness: .local, relevance: 70, exactMatch: true)
    }
}
