import Foundation

enum AppointmentCategory: String, Codable, CaseIterable, Sendable {
    case dentist, doctor, salon, barber, carService, tireService, veterinarian, repair, other
}
enum AppointmentBookingState: String, Codable, Sendable { case confirmed, cancelled }

struct AppointmentSearchRequest: Equatable, Codable, Sendable {
    let category: AppointmentCategory
    let latitude: Double
    let longitude: Double
    let interval: DateInterval
    let earliestHour: Int?
    let maximumPrice: Money?
    let minimumRating: Double?
}

struct AppointmentSlot: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let providerID: String
    let businessID: String
    let businessName: String
    let category: AppointmentCategory
    let interval: DateInterval
    let price: Money?
    let rating: Double?
    let latitude: Double
    let longitude: Double
    let availabilityVerified: Bool
    let observedAt: Date
    let sourceReference: String
    let officialBookingURL: URL?
}

struct AppointmentBooking: Equatable, Codable, Sendable {
    let id: String
    let providerID: String
    let slot: AppointmentSlot
    let state: AppointmentBookingState
    let providerReference: String
    let observedAt: Date
}

protocol AppointmentProvider: Sendable {
    var providerID: String { get }
    func search(_ request: AppointmentSearchRequest) async throws -> [AppointmentSlot]
    func book(slotID: String) async throws -> AppointmentBooking
    func reschedule(bookingID: String, slotID: String) async throws -> AppointmentBooking
    func cancel(bookingID: String) async throws -> AppointmentBooking
}

struct AppointmentSearchResult: Equatable, Sendable {
    let slots: [AppointmentSlot]
    let failures: [String: String]
}
enum AppointmentExecution: Equatable, Sendable {
    case booked(AppointmentBooking)
    case handoff(URL)
    case phoneOrNavigationRequired
}
struct AppointmentLinkage: Equatable, Sendable {
    let calendar: CalendarEventDraft
    let departureAt: Date
    let routeSource: String
}
enum AppointmentError: Error, Equatable { case unverifiedSlot, confirmationRequired, providerMismatch, unverifiedMutation }

struct AppointmentEngine: Sendable {
    let providers: [any AppointmentProvider]
    let timeout: Duration
    let maximumEvidenceAge: TimeInterval

    init(providers: [any AppointmentProvider], timeout: Duration = .seconds(5), maximumEvidenceAge: TimeInterval = 900) {
        self.providers = Array(providers.prefix(6)); self.timeout = timeout; self.maximumEvidenceAge = maximumEvidenceAge
    }

    func search(_ request: AppointmentSearchRequest, now: Date = .now) async -> AppointmentSearchResult {
        let responses = await withTaskGroup(of: (String, Result<[AppointmentSlot], Error>).self) { group in
            for provider in providers { group.addTask { await fetch(provider, request, timeout: timeout) } }
            var values: [(String, Result<[AppointmentSlot], Error>)] = []
            for await value in group { values.append(value) }
            return values
        }
        var slots: [AppointmentSlot] = [], failures: [String: String] = [:]
        for (providerID, response) in responses {
            switch response {
            case .failure: failures[providerID] = "provider_error"
            case .success(let values): slots += values.filter { usable($0, providerID, request, now) }
            }
        }
        return .init(slots: slots.sorted { left, right in
            if left.interval.start != right.interval.start { return left.interval.start < right.interval.start }
            if left.price?.amount != right.price?.amount { return (left.price?.amount ?? .greatestFiniteMagnitude) < (right.price?.amount ?? .greatestFiniteMagnitude) }
            return left.id < right.id
        }, failures: failures)
    }

    func book(_ slot: AppointmentSlot, confirmed: Bool, now: Date = .now) async throws -> AppointmentExecution {
        try requireVerified(slot, now)
        guard confirmed else { throw AppointmentError.confirmationRequired }
        guard let provider = providers.first(where: { $0.providerID == slot.providerID }) else {
            if let url = slot.officialBookingURL, url.scheme == "https" { return .handoff(url) }
            return .phoneOrNavigationRequired
        }
        let booking = try await provider.book(slotID: slot.id)
        guard booking.providerID == provider.providerID, booking.slot.id == slot.id,
              booking.state == .confirmed, !booking.providerReference.isEmpty else { throw AppointmentError.unverifiedMutation }
        return .booked(booking)
    }

    func reschedule(_ booking: AppointmentBooking, to slot: AppointmentSlot, confirmed: Bool) async throws -> AppointmentBooking {
        guard confirmed else { throw AppointmentError.confirmationRequired }
        guard booking.providerID == slot.providerID,
              let provider = providers.first(where: { $0.providerID == booking.providerID }) else { throw AppointmentError.providerMismatch }
        let updated = try await provider.reschedule(bookingID: booking.id, slotID: slot.id)
        guard updated.id == booking.id, updated.slot.id == slot.id, updated.state == .confirmed,
              !updated.providerReference.isEmpty else { throw AppointmentError.unverifiedMutation }
        return updated
    }

    func cancel(_ booking: AppointmentBooking, confirmed: Bool) async throws -> AppointmentBooking {
        guard confirmed else { throw AppointmentError.confirmationRequired }
        guard let provider = providers.first(where: { $0.providerID == booking.providerID }) else { throw AppointmentError.providerMismatch }
        let cancelled = try await provider.cancel(bookingID: booking.id)
        guard cancelled.id == booking.id, cancelled.state == .cancelled,
              !cancelled.providerReference.isEmpty else { throw AppointmentError.unverifiedMutation }
        return cancelled
    }

    func linkage(for booking: AppointmentBooking, route: RouteResult, buffer: TimeInterval = 600) throws -> AppointmentLinkage {
        guard booking.state == .confirmed, !route.source.isEmpty, route.expectedTravelTime >= 0 else {
            throw AppointmentError.unverifiedMutation
        }
        return .init(calendar: .init(title: booking.slot.businessName, start: booking.slot.interval.start,
                                     end: booking.slot.interval.end, notes: booking.providerReference),
                     departureAt: booking.slot.interval.start.addingTimeInterval(-route.expectedTravelTime-buffer),
                     routeSource: route.source)
    }

    private func requireVerified(_ slot: AppointmentSlot, _ now: Date) throws {
        let age = now.timeIntervalSince(slot.observedAt)
        guard slot.availabilityVerified, age >= -60, age <= maximumEvidenceAge,
              !slot.sourceReference.isEmpty else { throw AppointmentError.unverifiedSlot }
    }
    private func usable(_ slot: AppointmentSlot, _ providerID: String, _ request: AppointmentSearchRequest, _ now: Date) -> Bool {
        guard slot.providerID == providerID, slot.category == request.category,
              request.interval.contains(slot.interval.start), slot.interval.end <= request.interval.end,
              (try? { try requireVerified(slot, now); return true }()) == true else { return false }
        if let hour = request.earliestHour, Calendar(identifier: .gregorian).component(.hour, from: slot.interval.start) < hour { return false }
        if let maximum = request.maximumPrice {
            guard let price = slot.price, price.currency == maximum.currency, price.amount <= maximum.amount else { return false }
        }
        if let rating = request.minimumRating, (slot.rating ?? -1) < rating { return false }
        return true
    }
    private func fetch(_ provider: any AppointmentProvider, _ request: AppointmentSearchRequest,
                       timeout: Duration) async -> (String, Result<[AppointmentSlot], Error>) {
        do {
            let value = try await withThrowingTaskGroup(of: [AppointmentSlot].self) { group in
                group.addTask { try await provider.search(request) }
                group.addTask { try await Task.sleep(for: timeout); throw CancellationError() }
                let first = try await group.next() ?? []; group.cancelAll(); return first
            }
            return (provider.providerID, .success(value))
        } catch { return (provider.providerID, .failure(error)) }
    }
}
