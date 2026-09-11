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

private actor RestaurantHTTPRecorder: RestaurantHTTPTransport {
    var responses: [(Data, Int)]
    private(set) var requests: [URLRequest] = []
    init(_ responses: [(Data, Int)]) { self.responses = responses }
    func data(for request: URLRequest) throws -> (Data, Int) {
        requests.append(request)
        return responses.removeFirst()
    }
    func recorded() -> [URLRequest] { requests }
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

    @Test func officialHTTPAdapterInjectsCredentialAndParsesAvailabilityAndBooking() async throws {
        let interval = DateInterval(start: .now.addingTimeInterval(600), duration: 1_800)
        let slot = RestaurantReservationSlot(id: "slot-1", providerID: "official", restaurantID: "r1",
            interval: interval, partySize: 2, availabilityVerified: true, observedAt: .now,
            sourceReference: "official:slot-1")
        let booking = RestaurantReservation(id: "booking-1", providerID: "official", slotID: slot.id,
            state: .confirmed, providerReference: "official:booking-1", observedAt: .now)
        let transport = RestaurantHTTPRecorder([(try JSONEncoder().encode([slot]), 200),
                                                 (try JSONEncoder().encode(booking), 200)])
        let provider = try OfficialRestaurantHTTPProvider(configuration: .init(providerID: "official",
            availabilityURL: URL(string: "https://booking.example/availability")!,
            bookingURL: URL(string: "https://booking.example/bookings")!),
            bearerToken: "secret", transport: transport)
        #expect(try await provider.availability(restaurantID: "r1", partySize: 2, interval: interval) == [slot])
        #expect(try await provider.book(slotID: slot.id) == booking)
        let requests = await transport.recorded()
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer secret" })
        let availabilityBody = try #require(requests[0].httpBody)
        let availabilityJSON = try #require(JSONSerialization.jsonObject(with: availabilityBody) as? [String: Any])
        #expect(availabilityJSON["restaurantID"] as? String == "r1")
        #expect(availabilityJSON["partySize"] as? Int == 2)
        let bookingBody = try #require(requests[1].httpBody)
        let bookingJSON = try #require(JSONSerialization.jsonObject(with: bookingBody) as? [String: String])
        #expect(bookingJSON["slotID"] == slot.id)
    }

    @Test func officialHTTPAdapterRejectsMissingCredentialAndMapsProviderErrors() async throws {
        let config = RestaurantProviderConfiguration(providerID: "official",
            availabilityURL: URL(string: "https://booking.example/availability")!,
            bookingURL: URL(string: "https://booking.example/bookings")!)
        #expect(throws: RestaurantHTTPError.missingCredential) {
            try OfficialRestaurantHTTPProvider(configuration: config, bearerToken: " ")
        }
        let provider = try OfficialRestaurantHTTPProvider(configuration: config, bearerToken: "token",
            transport: RestaurantHTTPRecorder([(Data("{}".utf8), 429)]))
        await #expect(throws: RestaurantHTTPError.rateLimited) {
            try await provider.availability(restaurantID: "r1", partySize: 2,
                interval: .init(start: .now, duration: 3_600))
        }
    }

    @Test func officialHTTPAdapterUsesConfiguredTypedMutationBoundaries() async throws {
        let current = RestaurantReservation(id: "booking-7", providerID: "official", slotID: "slot-1",
            state: .confirmed, providerReference: "official:booking-7", observedAt: .now)
        let modified = RestaurantReservation(id: current.id, providerID: current.providerID, slotID: "slot-2",
            state: .confirmed, providerReference: "official:booking-7:modified", observedAt: .now)
        let cancelled = RestaurantReservation(id: current.id, providerID: current.providerID, slotID: modified.slotID,
            state: .cancelled, providerReference: "official:booking-7:cancelled", observedAt: .now)
        let transport = RestaurantHTTPRecorder([
            (try JSONEncoder().encode(modified), 200),
            (try JSONEncoder().encode(cancelled), 200)
        ])
        let provider = try OfficialRestaurantHTTPProvider(configuration: .init(
            providerID: "official",
            availabilityURL: URL(string: "https://booking.example/availability")!,
            bookingURL: URL(string: "https://booking.example/bookings")!,
            modificationURL: URL(string: "https://booking.example/bookings/modify")!,
            cancellationURL: URL(string: "https://booking.example/bookings/cancel")!
        ), bearerToken: "secret", transport: transport)

        #expect(provider.capabilities == [.availability, .booking, .modification, .cancellation])
        #expect(try await provider.modify(bookingID: current.id, slotID: modified.slotID) == modified)
        #expect(try await provider.cancel(bookingID: current.id) == cancelled)

        let requests = await transport.recorded()
        #expect(requests.map(\.url?.path) == ["/bookings/modify", "/bookings/cancel"])
        #expect(requests.allSatisfy { $0.httpMethod == "POST" })
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer secret" })
        let modifyBody = try #require(requests[0].httpBody)
        let modifyJSON = try #require(JSONSerialization.jsonObject(with: modifyBody) as? [String: String])
        #expect(modifyJSON["bookingID"] == current.id)
        #expect(modifyJSON["slotID"] == modified.slotID)
        let cancelBody = try #require(requests[1].httpBody)
        let cancelJSON = try #require(JSONSerialization.jsonObject(with: cancelBody) as? [String: String])
        #expect(cancelJSON["bookingID"] == current.id)
    }

    @Test func mutationWithoutConfiguredProviderBoundaryFailsTruthfully() async throws {
        let config = RestaurantProviderConfiguration(providerID: "official",
            availabilityURL: URL(string: "https://booking.example/availability")!,
            bookingURL: URL(string: "https://booking.example/bookings")!)
        let provider = try OfficialRestaurantHTTPProvider(configuration: config, bearerToken: "token",
            transport: RestaurantHTTPRecorder([]))
        #expect(provider.capabilities == [.availability, .booking])
        await #expect(throws: RestaurantDiscoveryError.providerOperationUnavailable) {
            try await provider.modify(bookingID: "booking-8", slotID: "slot-9")
        }
        await #expect(throws: RestaurantDiscoveryError.providerOperationUnavailable) {
            try await provider.cancel(bookingID: "booking-8")
        }
    }
}
