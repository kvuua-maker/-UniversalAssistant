import Foundation
import Testing
@testable import UniversalAssistant

private struct FavoriteRefreshStub: FavoriteRefreshing {
    let value: FavoriteReference
    func refresh(_ favorite: FavoriteReference) async throws -> FavoriteReference { value }
}

@Suite("Personal tasks and favorites") struct PersonalHubTests {
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("ua-personal-hub-\(UUID())") }

    @Test func favoritePersistsOnlyBoundedMinimalReferenceAndNeverCreatesAWatch() async throws {
        let directory = directory(), local = LocalStore(baseDirectory: directory)
        let store = FavoriteStore(store: local, maximumCount: 1)
        try await store.save(.init(id: "shoe", kind: .product, providerID: "shop", externalReference: "sku-1", displayTitle: "Shoe"))
        try await store.save(.init(id: "place", kind: .place, providerID: "maps", externalReference: "place-1", displayTitle: "Cafe"))
        let restored = FavoriteStore(store: local, maximumCount: 1)
        try await restored.restore()
        let values = await restored.snapshot()
        #expect(values.map(\.id) == ["place"])
        #expect(values[0].freshness == .unknown)
    }

    @Test func openingFavoriteRefreshesMutableTruthOrKeepsUnknown() async throws {
        let store = FavoriteStore(store: LocalStore(baseDirectory: directory()))
        let original = FavoriteReference(id: "shoe", kind: .product, providerID: "shop", externalReference: "sku-1", displayTitle: "Shoe")
        try await store.save(original)
        let now = Date()
        let fresh = FavoriteReference(id: "shoe", kind: .product, providerID: "shop", externalReference: "sku-1", displayTitle: "Shoe", mutableSummary: "120 UAH", sourceUpdatedAt: now, freshness: .current)
        let result = try await store.refresh(id: "shoe", using: FavoriteRefreshStub(value: fresh), now: now)
        #expect(result.freshness == .current)
        #expect(result.lastRefreshAttemptAt == now)
    }

    @Test func refreshCannotSwapProviderIdentity() async throws {
        let store = FavoriteStore(store: LocalStore(baseDirectory: directory()))
        let original = FavoriteReference(id: "shoe", kind: .product, providerID: "shop", externalReference: "sku-1", displayTitle: "Shoe")
        try await store.save(original)
        let wrong = FavoriteReference(id: "shoe", kind: .product, providerID: "other", externalReference: "sku-1", displayTitle: "Shoe")
        await #expect(throws: FavoriteStoreError.providerMismatch) { try await store.refresh(id: "shoe", using: FavoriteRefreshStub(value: wrong)) }
    }

    @Test func myTasksAggregatesReferencesWithoutCopyingSystemRecordsOrUnreadBadges() {
        let now = Date(), hub = PersonalTaskHub()
        let appointment = PersonalTaskItem(id: "a", kind: .appointment, source: .systemReference, externalReference: "event-id", title: "Dentist", status: .confirmed, relevantAt: now, verifiedAt: now)
        let action = PersonalTaskItem(id: "b", kind: .booking, source: .provider, externalReference: "booking-id", title: "Confirm arrival", status: .actionRequired, relevantAt: now, verifiedAt: now)
        let duplicate = PersonalTaskItem(id: "c", kind: .booking, source: .provider, externalReference: "booking-id", title: "Old", status: .pending, relevantAt: now, verifiedAt: .distantPast)
        let result = hub.aggregate(assistantOwned: [action, duplicate], systemReferences: [appointment])
        #expect(result.count == 2)
        #expect(result.first?.id == "b")
        #expect(result.filter(\.requiresAttention).count == 1)
    }
}
