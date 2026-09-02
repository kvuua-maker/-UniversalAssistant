import Foundation
import Testing
@testable import UniversalAssistant

private actor AppointmentFake: AppointmentProvider {
    nonisolated let providerID = "provider"
    let slots: [AppointmentSlot]
    init(_ slots: [AppointmentSlot]) { self.slots = slots }
    func search(_ request: AppointmentSearchRequest) -> [AppointmentSlot] { slots }
    func book(slotID: String) throws -> AppointmentBooking { try booking(slotID, state: .confirmed, id: "booking-1") }
    func reschedule(bookingID: String, slotID: String) throws -> AppointmentBooking { try booking(slotID, state: .confirmed, id: bookingID) }
    func cancel(bookingID: String) throws -> AppointmentBooking { try booking(slots[0].id, state: .cancelled, id: bookingID) }
    private func booking(_ slotID: String, state: AppointmentBookingState, id: String) throws -> AppointmentBooking {
        let slot = try #require(slots.first { $0.id == slotID })
        return .init(id: id, providerID: providerID, slot: slot, state: state,
                     providerReference: "provider:\(id):\(state.rawValue)", observedAt: .now)
    }
}

private actor AppointmentHTTPRecorder: AppointmentHTTPTransport {
    var responses: [(Data, Int)]
    private(set) var requests: [URLRequest] = []
    init(_ responses: [(Data, Int)]) { self.responses = responses }
    func data(for request: URLRequest) throws -> (Data, Int) {
        requests.append(request)
        return responses.removeFirst()
    }
    func recorded() -> [URLRequest] { requests }
}

private func appointmentSlot(_ id: String, start: Date, verified: Bool = true,
                             price: Decimal = 500) -> AppointmentSlot {
    .init(id: id, providerID: "provider", businessID: "service-1", businessName: "Шиномонтаж",
          category: .tireService, interval: .init(start: start, duration: 3600),
          price: .init(amount: price, currency: "UAH"), rating: 4.8,
          latitude: 50.45, longitude: 30.52, availabilityVerified: verified,
          observedAt: .now, sourceReference: "provider:\(id)",
          officialBookingURL: URL(string: "https://booking.example/slots/\(id)"))
}

@Suite("Appointment engine") struct AppointmentEngineTests {
    @Test func searchEnforcesRealAvailabilityTimePriceAndRating() async {
        let day = Date.now.addingTimeInterval(86_400)
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(bySettingHour: 16, minute: 0, second: 0, of: day)!
        let slots = [appointmentSlot("valid", start: start),
                     appointmentSlot("unverified", start: start.addingTimeInterval(3600), verified: false),
                     appointmentSlot("expensive", start: start.addingTimeInterval(7200), price: 2000)]
        let result = await AppointmentEngine(providers: [AppointmentFake(slots)]).search(
            .init(category: .tireService, latitude: 50.4, longitude: 30.5,
                  interval: .init(start: calendar.startOfDay(for: day), duration: 86_400),
                  earliestHour: 15, maximumPrice: .init(amount: 1000, currency: "UAH"), minimumRating: 4.5))
        #expect(result.slots.map(\.id) == ["valid"])
    }

    @Test func confirmedBookingRescheduleAndCancelRequireAuthoritativeProviderState() async throws {
        let first = appointmentSlot("first", start: .now.addingTimeInterval(7200))
        let second = appointmentSlot("second", start: .now.addingTimeInterval(10_800))
        let provider = AppointmentFake([first, second]), engine = AppointmentEngine(providers: [provider])
        await #expect(throws: AppointmentError.confirmationRequired) { try await engine.book(first, confirmed: false) }
        guard case let .booked(booking) = try await engine.book(first, confirmed: true) else {
            Issue.record("Expected verified booking"); return
        }
        let moved = try await engine.reschedule(booking, to: second, confirmed: true)
        #expect(moved.slot.id == "second")
        let cancelled = try await engine.cancel(moved, confirmed: true)
        #expect(cancelled.state == .cancelled)
    }

    @Test func staleOrUnverifiedSlotCanNeverBecomeBookingOrHandoff() async {
        var slot = appointmentSlot("bad", start: .now.addingTimeInterval(7200), verified: false)
        let engine = AppointmentEngine(providers: [])
        await #expect(throws: AppointmentError.unverifiedSlot) { try await engine.book(slot, confirmed: true) }
        slot = .init(id: slot.id, providerID: slot.providerID, businessID: slot.businessID,
            businessName: slot.businessName, category: slot.category, interval: slot.interval,
            price: slot.price, rating: slot.rating, latitude: slot.latitude, longitude: slot.longitude,
            availabilityVerified: true, observedAt: .now.addingTimeInterval(-3600),
            sourceReference: slot.sourceReference, officialBookingURL: slot.officialBookingURL)
        await #expect(throws: AppointmentError.unverifiedSlot) { try await engine.book(slot, confirmed: true) }
    }

    @Test func confirmedBookingCreatesCalendarAndVerifiedDeparturePlan() throws {
        let slot = appointmentSlot("first", start: .now.addingTimeInterval(7200))
        let booking = AppointmentBooking(id: "b", providerID: "provider", slot: slot, state: .confirmed,
            providerReference: "provider:b", observedAt: .now)
        let route = RouteResult(distanceMeters: 5000, expectedTravelTime: 1200,
                                steps: [], source: "mapkit", timestamp: .now)
        let linkage = try AppointmentEngine(providers: []).linkage(for: booking, route: route, buffer: 600)
        #expect(linkage.calendar.start == slot.interval.start)
        #expect(linkage.departureAt == slot.interval.start.addingTimeInterval(-1800))
        #expect(linkage.routeSource == "mapkit")
    }

    @Test func httpAdapterInjectsCredentialAndParsesRealSearchAndBookingResponses() async throws {
        let slot = appointmentSlot("slot-1", start: .now.addingTimeInterval(7200))
        let booking = AppointmentBooking(id: "booking-1", providerID: "provider", slot: slot,
            state: .confirmed, providerReference: "provider:booking-1", observedAt: .now)
        let transport = AppointmentHTTPRecorder([(try JSONEncoder().encode([slot]), 200),
                                                  (try JSONEncoder().encode(booking), 200)])
        let provider = try OfficialAppointmentHTTPProvider(configuration: .init(providerID: "provider",
            searchURL: URL(string: "https://appointments.example/search")!,
            bookingURL: URL(string: "https://appointments.example/bookings")!),
            bearerToken: "secret", transport: transport)
        let day = DateInterval(start: .now, duration: 86_400)
        #expect(try await provider.search(.init(category: .tireService, latitude: 50, longitude: 30,
            interval: day, earliestHour: 15, maximumPrice: nil, minimumRating: nil)) == [slot])
        #expect(try await provider.book(slotID: slot.id) == booking)
        let requests = await transport.recorded()
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer secret" })
        #expect(requests[1].url?.path == "/bookings/book")
        let body = try #require(requests[1].httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(object["slot_id"] == slot.id)
    }

    @Test func httpAdapterRejectsBlankCredentialAndMapsRateLimit() async throws {
        let config = AppointmentProviderConfiguration(providerID: "p",
            searchURL: URL(string: "https://appointments.example/search")!,
            bookingURL: URL(string: "https://appointments.example/bookings")!)
        #expect(throws: AppointmentHTTPError.missingCredential) {
            try OfficialAppointmentHTTPProvider(configuration: config, bearerToken: " ")
        }
        let provider = try OfficialAppointmentHTTPProvider(configuration: config, bearerToken: "token",
            transport: AppointmentHTTPRecorder([(Data("{}".utf8), 429)]))
        await #expect(throws: AppointmentHTTPError.rateLimited) {
            try await provider.search(.init(category: .salon, latitude: 50, longitude: 30,
                interval: .init(start: .now, duration: 3600), earliestHour: nil,
                maximumPrice: nil, minimumRating: nil))
        }
    }
}
