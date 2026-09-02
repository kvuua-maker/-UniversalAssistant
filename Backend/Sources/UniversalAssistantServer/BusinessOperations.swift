import Foundation

enum BusinessInteractionSource: String, Codable, Sendable { case universalAssistant, partnerAPI, website, email, messaging, marketplace }
enum BusinessInteractionStatus: String, Codable, Sendable { case open, assigned, resolved, unavailable }

struct PartnerCustomer: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let partnerID: UUID
    let identityKey: String
    var displayName: String?
    var permittedEmail: String?
    var permittedPhone: String?
    let createdAt: Date
    var updatedAt: Date
}

struct BusinessInteraction: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let partnerID: UUID
    let eventID: String
    let source: BusinessInteractionSource
    let sourceReference: String
    let customerID: UUID
    let occurredAt: Date
    let inquiryReference: String
    let category: String
    var relatedTransactionID: UUID?
    var status: BusinessInteractionStatus
    var assigneeReference: String?
}

enum BusinessTransactionDomain: String, Codable, Sendable { case order, booking, appointment, service }
enum BusinessTransactionState: String, Codable, Sendable {
    case created, confirmed, paid, inProgress, fulfilling, completed
    case cancelled, refunded, partiallyRefunded, disputed, failed, expired, noShow, rejected
}

struct BusinessTransactionEvent: Equatable, Codable, Sendable {
    let eventID: String
    let from: BusinessTransactionState
    let to: BusinessTransactionState
    let reasonCode: String
    let evidenceReference: String
    let occurredAt: Date
}

struct BusinessTransaction: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let partnerID: UUID
    let domain: BusinessTransactionDomain
    let externalID: String
    let customerID: UUID?
    let attributionID: UUID?
    let conversionID: UUID?
    var state: BusinessTransactionState
    var events: [BusinessTransactionEvent]
}

enum CatalogAvailability: String, Codable, Sendable { case available, unavailable, unknown }
struct CatalogFieldEvidence: Equatable, Codable, Sendable { let source: String; let observedAt: Date }
struct PartnerCatalogVariant: Identifiable, Equatable, Codable, Sendable {
    let id: String
    var attributes: [String: String]
    var price: LedgerMoney?
    var stockQuantity: Decimal?
    var availability: CatalogAvailability
}
struct PartnerCatalogItem: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let partnerID: UUID
    let providerID: String
    let externalID: String
    var sku: String?
    var title: String
    var itemDescription: String?
    var category: String
    var imageURLs: [URL]
    var variants: [PartnerCatalogVariant]
    var actionURL: URL?
    var fieldEvidence: [String: CatalogFieldEvidence]
    var sourceTimestamp: Date
    var deleted: Bool
}

enum PartnerConnectorCapability: String, Codable, CaseIterable, Sendable {
    case catalogRead, catalogSync, priceStockSync, orderIngest, orderStatusSync
    case bookingSync, appointmentSync, customerInquirySync, deliveryTracking
    case refundCancellation, webhookIngestion, healthStatus
}
struct PartnerConnectorDescriptor: Equatable, Codable, Sendable {
    let connectorID: String
    let partnerID: UUID
    let capabilities: Set<PartnerConnectorCapability>
}
protocol PartnerBusinessConnector: Sendable {
    var descriptor: PartnerConnectorDescriptor { get }
    func health() async throws -> PartnerHealthState
}

enum BusinessOperationsError: Error, Equatable, Sendable {
    case invalidRecord, duplicateExternalTransaction, invalidTransition, capabilityMismatch, staleUpdate
}

private struct BusinessOperationsSnapshot: Codable, Sendable {
    var customers: [PartnerCustomer] = []
    var interactions: [BusinessInteraction] = []
    var transactions: [BusinessTransaction] = []
    var catalog: [PartnerCatalogItem] = []
    var processedEventIDs: Set<String> = []
}

actor BusinessOperationsStore {
    private var snapshot: BusinessOperationsSnapshot
    private let persistenceURL: URL?

    init(persistenceURL: URL? = nil) throws {
        self.persistenceURL = persistenceURL
        if let persistenceURL, let data = try? Data(contentsOf: persistenceURL) {
            snapshot = try JSONDecoder().decode(BusinessOperationsSnapshot.self, from: data)
        } else { snapshot = .init() }
    }

    func upsertCustomer(partnerID: UUID, externalReference: String?, displayName: String?,
                        permittedEmail: String?, permittedPhone: String?, at: Date = .now) throws -> PartnerCustomer {
        let key = try Self.identityKey(externalReference: externalReference, email: permittedEmail, phone: permittedPhone)
        if let index = snapshot.customers.firstIndex(where: { $0.partnerID == partnerID && $0.identityKey == key }) {
            snapshot.customers[index].displayName = displayName ?? snapshot.customers[index].displayName
            snapshot.customers[index].permittedEmail = permittedEmail ?? snapshot.customers[index].permittedEmail
            snapshot.customers[index].permittedPhone = permittedPhone ?? snapshot.customers[index].permittedPhone
            snapshot.customers[index].updatedAt = at
            try persist(); return snapshot.customers[index]
        }
        let value = PartnerCustomer(id: UUID(), partnerID: partnerID, identityKey: key,
                                    displayName: displayName, permittedEmail: permittedEmail,
                                    permittedPhone: permittedPhone, createdAt: at, updatedAt: at)
        snapshot.customers.append(value); try persist(); return value
    }

    func ingestInteraction(_ value: BusinessInteraction) throws -> BusinessInteraction {
        guard snapshot.customers.contains(where: { $0.id == value.customerID && $0.partnerID == value.partnerID }),
              !value.eventID.isEmpty, !value.sourceReference.isEmpty else { throw BusinessOperationsError.invalidRecord }
        if let existing = snapshot.interactions.first(where: { $0.partnerID == value.partnerID && $0.eventID == value.eventID }) { return existing }
        snapshot.interactions.append(value); snapshot.processedEventIDs.insert(value.eventID); try persist(); return value
    }

    func inbox(partnerID: UUID) -> [BusinessInteraction] {
        snapshot.interactions.filter { $0.partnerID == partnerID }.sorted { $0.occurredAt > $1.occurredAt }
    }

    func createTransaction(_ value: BusinessTransaction) throws -> BusinessTransaction {
        guard !value.externalID.isEmpty, value.state == .created,
              !snapshot.transactions.contains(where: { $0.partnerID == value.partnerID && $0.domain == value.domain && $0.externalID == value.externalID })
        else { throw BusinessOperationsError.duplicateExternalTransaction }
        snapshot.transactions.append(value); try persist(); return value
    }

    func transition(transactionID: UUID, eventID: String, to next: BusinessTransactionState,
                    reason: String, evidence: String, at: Date = .now) throws -> BusinessTransaction {
        guard let index = snapshot.transactions.firstIndex(where: { $0.id == transactionID }),
              !eventID.isEmpty, !reason.isEmpty, !evidence.isEmpty else { throw BusinessOperationsError.invalidRecord }
        if snapshot.processedEventIDs.contains(eventID) { return snapshot.transactions[index] }
        let current = snapshot.transactions[index].state
        guard Self.allowed(current, next, domain: snapshot.transactions[index].domain) else { throw BusinessOperationsError.invalidTransition }
        snapshot.transactions[index].events.append(.init(eventID: eventID, from: current, to: next,
                                                         reasonCode: reason, evidenceReference: evidence, occurredAt: at))
        snapshot.transactions[index].state = next; snapshot.processedEventIDs.insert(eventID)
        try persist(); return snapshot.transactions[index]
    }

    func applyCatalog(eventID: String, items: [PartnerCatalogItem]) throws {
        if snapshot.processedEventIDs.contains(eventID) { return }
        guard !eventID.isEmpty else { throw BusinessOperationsError.invalidRecord }
        for item in items {
            guard !item.id.isEmpty, !item.externalID.isEmpty, !item.title.isEmpty,
                  item.variants.allSatisfy({ variant in
                      (variant.price?.amount ?? 0) >= 0 && (variant.stockQuantity ?? 0) >= 0
                  }) else { throw BusinessOperationsError.invalidRecord }
            if let index = snapshot.catalog.firstIndex(where: { $0.partnerID == item.partnerID && $0.providerID == item.providerID && $0.externalID == item.externalID }) {
                guard item.sourceTimestamp >= snapshot.catalog[index].sourceTimestamp else { throw BusinessOperationsError.staleUpdate }
                snapshot.catalog[index] = item
            } else { snapshot.catalog.append(item) }
        }
        snapshot.processedEventIDs.insert(eventID); try persist()
    }

    func catalog(partnerID: UUID, now: Date = .now, maximumAge: TimeInterval) -> [PartnerCatalogItem] {
        snapshot.catalog.filter { $0.partnerID == partnerID && !$0.deleted && now.timeIntervalSince($0.sourceTimestamp) <= maximumAge }
    }

    func require(_ capability: PartnerConnectorCapability, from connector: any PartnerBusinessConnector) throws {
        guard connector.descriptor.capabilities.contains(capability) else { throw BusinessOperationsError.capabilityMismatch }
    }

    private func persist() throws {
        guard let persistenceURL else { return }
        try FileManager.default.createDirectory(at: persistenceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: persistenceURL, options: .atomic)
    }

    private static func identityKey(externalReference: String?, email: String?, phone: String?) throws -> String {
        if let externalReference, !externalReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "external:" + externalReference.lowercased()
        }
        if let email, !email.isEmpty { return "email:" + email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if let phone {
            let normalized = phone.filter { $0.isNumber }
            if normalized.count >= 7 { return "phone:" + normalized }
        }
        throw BusinessOperationsError.invalidRecord
    }

    private static func allowed(_ from: BusinessTransactionState, _ to: BusinessTransactionState,
                                domain: BusinessTransactionDomain) -> Bool {
        switch (from, to) {
        case (.created, .confirmed), (.created, .rejected), (.created, .failed), (.created, .expired),
             (.confirmed, .paid), (.confirmed, .inProgress), (.confirmed, .fulfilling), (.confirmed, .cancelled),
             (.confirmed, .noShow), (.paid, .inProgress), (.paid, .fulfilling), (.paid, .cancelled),
             (.inProgress, .completed), (.inProgress, .cancelled), (.fulfilling, .completed),
             (.fulfilling, .cancelled), (.completed, .refunded), (.completed, .partiallyRefunded),
             (.completed, .disputed), (.partiallyRefunded, .refunded), (.disputed, .refunded),
             (.disputed, .completed): return true
        case (.confirmed, .completed): return domain == .booking || domain == .appointment
        default: return false
        }
    }
}
