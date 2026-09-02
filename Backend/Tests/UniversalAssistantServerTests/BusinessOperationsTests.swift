import Foundation
import Testing
@testable import UniversalAssistantServer

private struct FixtureBusinessConnector: PartnerBusinessConnector {
    let descriptor: PartnerConnectorDescriptor
    var fails = false
    func health() async throws -> PartnerHealthState {
        if fails { throw BusinessOperationsError.invalidRecord }
        return .activeHealthy
    }
}

@Suite("Partner business operations") struct BusinessOperationsTests {
    private func transaction(partner: UUID, customer: UUID? = nil, domain: BusinessTransactionDomain = .order) -> BusinessTransaction {
        .init(id: UUID(), partnerID: partner, domain: domain, externalID: UUID().uuidString,
              customerID: customer, attributionID: UUID(), conversionID: UUID(), state: .created, events: [])
    }

    private func catalog(partner: UUID, time: Date, price: Decimal = 10, stock: Decimal = 2,
                         deleted: Bool = false) -> PartnerCatalogItem {
        .init(id: "local", partnerID: partner, providerID: "erp", externalID: "external-1", sku: "SKU-1",
              title: "Product", itemDescription: nil, category: "goods", imageURLs: [],
              variants: [.init(id: "black-M", attributes: ["color": "black", "size": "M"],
                               price: .init(amount: price, currencyCode: "EUR"), stockQuantity: stock,
                               availability: stock > 0 ? .available : .unavailable)],
              actionURL: URL(string: "https://partner.example/product/1"),
              fieldEvidence: ["price": .init(source: "erp", observedAt: time),
                              "stock": .init(source: "erp", observedAt: time)],
              sourceTimestamp: time, deleted: deleted)
    }

    @Test func customerDeduplicationInboxAttributionAndDuplicateEventPersistAcrossRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let url = directory.appending(path: "business.json")
        let partner = UUID()
        let first = try BusinessOperationsStore(persistenceURL: url)
        let customer = try await first.upsertCustomer(partnerID: partner, externalReference: "CRM-1", displayName: "A",
                                                      permittedEmail: "allowed@example.com", permittedPhone: nil)
        let duplicate = try await first.upsertCustomer(partnerID: partner, externalReference: "crm-1", displayName: "Updated",
                                                        permittedEmail: nil, permittedPhone: nil)
        #expect(customer.id == duplicate.id)
        let interaction = BusinessInteraction(id: UUID(), partnerID: partner, eventID: "event-1", source: .email,
                                              sourceReference: "provider-message-1", customerID: customer.id,
                                              occurredAt: .now, inquiryReference: "inquiry-1", category: "booking",
                                              relatedTransactionID: nil, status: .open, assigneeReference: nil)
        _ = try await first.ingestInteraction(interaction)
        _ = try await first.ingestInteraction(interaction)
        let restored = try BusinessOperationsStore(persistenceURL: url)
        let inbox = await restored.inbox(partnerID: partner)
        #expect(inbox.count == 1)
        #expect(inbox.first?.source == .email)
        #expect(inbox.first?.sourceReference == "provider-message-1")
    }

    @Test func catalogMapsSKUAppliesPriceStockDeletionAndRejectsStaleUpdate() async throws {
        let store = try BusinessOperationsStore()
        let partner = UUID(), now = Date.now
        try await store.applyCatalog(eventID: "one", items: [catalog(partner: partner, time: now)])
        try await store.applyCatalog(eventID: "two", items: [catalog(partner: partner, time: now.addingTimeInterval(1), price: 12, stock: 0)])
        var current = await store.catalog(partnerID: partner, now: now.addingTimeInterval(2), maximumAge: 60)
        #expect(current.first?.sku == "SKU-1")
        #expect(current.first?.variants.first?.price?.amount == 12)
        #expect(current.first?.variants.first?.availability == .unavailable)
        await #expect(throws: BusinessOperationsError.staleUpdate) {
            try await store.applyCatalog(eventID: "stale", items: [catalog(partner: partner, time: now)])
        }
        try await store.applyCatalog(eventID: "delete", items: [catalog(partner: partner, time: now.addingTimeInterval(2), deleted: true)])
        current = await store.catalog(partnerID: partner, now: now.addingTimeInterval(3), maximumAge: 60)
        #expect(current.isEmpty)
        #expect((await store.catalog(partnerID: partner, now: now.addingTimeInterval(100), maximumAge: 10)).isEmpty)
    }

    @Test func orderAndBookingTransitionsAreTypedIdempotentAndAudited() async throws {
        let store = try BusinessOperationsStore(), partner = UUID()
        let order = try await store.createTransaction(transaction(partner: partner))
        let confirmed = try await store.transition(transactionID: order.id, eventID: "confirm", to: .confirmed,
                                                   reason: "provider_confirmed", evidence: "webhook-1")
        let duplicate = try await store.transition(transactionID: order.id, eventID: "confirm", to: .confirmed,
                                                   reason: "provider_confirmed", evidence: "webhook-1")
        #expect(confirmed.events.count == 1 && duplicate.events.count == 1)
        await #expect(throws: BusinessOperationsError.invalidTransition) {
            try await store.transition(transactionID: order.id, eventID: "bad", to: .refunded,
                                       reason: "invalid", evidence: "webhook-2")
        }
        let cancelled = try await store.transition(transactionID: order.id, eventID: "cancel", to: .cancelled,
                                                   reason: "customer_cancelled", evidence: "webhook-3")
        #expect(cancelled.state == .cancelled)

        let booking = try await store.createTransaction(transaction(partner: partner, domain: .booking))
        _ = try await store.transition(transactionID: booking.id, eventID: "booking-confirm", to: .confirmed,
                                       reason: "slot_confirmed", evidence: "booking-provider")
        let completed = try await store.transition(transactionID: booking.id, eventID: "booking-complete", to: .completed,
                                                   reason: "attended", evidence: "booking-provider")
        #expect(completed.state == .completed)
        let disputed = try await store.transition(transactionID: booking.id, eventID: "dispute", to: .disputed,
                                                  reason: "customer_dispute", evidence: "case-1")
        #expect(disputed.state == .disputed)
    }

    @Test func connectorCapabilitiesAreExplicitAndOneFailureDoesNotBecomeEmptyData() async throws {
        let partner = UUID()
        let catalogConnector = FixtureBusinessConnector(descriptor: .init(connectorID: "catalog", partnerID: partner,
                                                                          capabilities: [.catalogSync, .healthStatus]))
        let failing = FixtureBusinessConnector(descriptor: .init(connectorID: "inbox", partnerID: partner,
                                                                 capabilities: [.customerInquirySync]), fails: true)
        let store = try BusinessOperationsStore()
        try await store.require(.catalogSync, from: catalogConnector)
        await #expect(throws: BusinessOperationsError.capabilityMismatch) { try await store.require(.orderIngest, from: catalogConnector) }
        #expect(try await catalogConnector.health() == .activeHealthy)
        await #expect(throws: BusinessOperationsError.invalidRecord) { try await failing.health() }
        try await store.applyCatalog(eventID: "catalog", items: [catalog(partner: partner, time: .now)])
        #expect((await store.catalog(partnerID: partner, maximumAge: 60)).count == 1)
    }
}
