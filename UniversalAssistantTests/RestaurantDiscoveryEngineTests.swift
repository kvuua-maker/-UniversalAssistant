import Foundation
import Testing
@testable import UniversalAssistant

private struct RestaurantProviderFake: ReservationProvider {
    let providerID = "tables"
    let slots: [RestaurantReservationSlot]
    let booking: RestaurantReservation
    func availability(restaurantID: String, partySize: Int, interval: DateInterval) async throws -> [RestaurantReservationSlot] { slots }
    func book(slotID: String) async throws -> RestaurantReservation { booking }
}

@Suite("Truthful restaurant discovery and reservation") struct RestaurantDiscoveryEngineTests {
    private func place(open: Bool = true) -> Place {
        Place(id: "r1", providerID: "maps", name: "Bistro", category: .restaurant,
              latitude: 50.45, longitude: 30.52, address: "Kyiv", distanceMeters: 700,
              phone: "+380441234567", officialWebsite: URL(string: "https://bistro.example/reserve"),
              rating: 4.7, reviewCount: 100, isOpenNow: open, priceLevel: 2,
              source: "maps", timestamp: .now, verification: .providerVerified)
    }

    @Test func filtersEverySupportedRestaurantConstraintUsingEvidence() throws {
        let offer = RestaurantOffer(id: "r1", place: place(), cuisines: ["Italian"],
            dietaryOptions: ["vegan"], evidenceTimestamp: .now, sourceReference: "maps:r1")
        let request = RestaurantSearchRequest(cuisine: "italian", maximumPriceLevel: 2,
            minimumRating: 4.5, maximumDistanceMeters: 1_000, openNow: true,
            partySize: 2, interval: DateInterval(start: .now, duration: 3_600),
            dietaryPreferences: ["vegan"])
        #expect(try RestaurantDiscoveryEngine(providers: []).filter([offer], request: request).map(\.id) == ["r1"])
    }

    @Test func onlyFreshVerifiedMatchingSlotsAreOffered() async {
        let interval = DateInterval(start: .now.addingTimeInterval(600), duration: 3_600)
        let slot = RestaurantReservationSlot(id: "s", providerID: "tables", restaurantID: "r1",
            interval: DateInterval(start: interval.start, duration: 3_600), partySize: 2,
            availabilityVerified: true, observedAt: .now, sourceReference: "tables:s")
        let booking = RestaurantReservation(id: "b", providerID: "tables", slotID: "s",
            state: .confirmed, providerReference: "tables:b", observedAt: .now)
        let engine = RestaurantDiscoveryEngine(providers: [RestaurantProviderFake(slots: [slot], booking: booking)])
        let offer = RestaurantOffer(id: "r1", place: place(), cuisines: [], dietaryOptions: [],
            evidenceTimestamp: .now, sourceReference: "maps:r1")
        let request = RestaurantSearchRequest(partySize: 2, interval: interval)
        #expect(await engine.availability(for: offer, request: request).map(\.id) == ["s"])
    }

    @Test func bookingRequiresConfirmationAndAuthoritativeConfirmedReadback() async throws {
        let slot = RestaurantReservationSlot(id: "s", providerID: "tables", restaurantID: "r1",
            interval: DateInterval(start: .now.addingTimeInterval(600), duration: 1_800), partySize: 2,
            availabilityVerified: true, observedAt: .now, sourceReference: "tables:s")
        let booking = RestaurantReservation(id: "b", providerID: "tables", slotID: "s",
            state: .confirmed, providerReference: "tables:b", observedAt: .now)
        let engine = RestaurantDiscoveryEngine(providers: [RestaurantProviderFake(slots: [slot], booking: booking)])
        await #expect(throws: RestaurantDiscoveryError.confirmationRequired) { try await engine.book(slot, confirmed: false) }
        #expect(try await engine.book(slot, confirmed: true) == .confirmed(booking))
    }

    @Test func fallbackUsesExactOfficialPageThenPhoneThenNavigation() throws {
        let engine = RestaurantDiscoveryEngine(providers: [])
        let offer = RestaurantOffer(id: "r1", place: place(), cuisines: [], dietaryOptions: [],
            evidenceTimestamp: .now, sourceReference: "maps:r1",
            officialBookingURL: URL(string: "https://bistro.example/table/2"))
        guard case .officialHandoff = try engine.fallback(for: offer) else { Issue.record("Expected official handoff"); return }
    }
}
