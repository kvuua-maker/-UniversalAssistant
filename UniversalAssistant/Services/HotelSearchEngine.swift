import Foundation

enum AccommodationKind: String, Codable, CaseIterable, Sendable {
    case hotel, apartment, hostel, guestHouse, other
}

enum HotelAvailabilityState: String, Codable, Sendable {
    case liveConfirmed, providerConfirmed, requestRequired, cachedRecent, unknown, unavailable

    var isVerifiedAvailable: Bool { self == .liveConfirmed || self == .providerConfirmed }
}

struct HotelAvailabilityEvidence: Equatable, Sendable {
    let state: HotelAvailabilityState
    let source: String?
    let observedAt: Date?
}

struct HotelPriceQuote: Equatable, Sendable {
    let knownTotal: Money?
    let nightlyRate: Money?
    let includesMandatoryFees: Bool
    let observedAt: Date?
}

struct HotelOffer: Identifiable, Equatable, Sendable {
    let id: String
    let providerID: String
    let providerOfferID: String
    let kind: AccommodationKind
    let name: String
    let locationLabel: String
    let stay: DateInterval
    let quotedGuestCount: Int
    let quotedRoomCount: Int
    let price: HotelPriceQuote
    let availability: HotelAvailabilityEvidence
    let exactBookingURL: URL
    let fetchedAt: Date
}

struct HotelSearchRequest: Equatable, Sendable {
    let location: String
    let checkIn: Date
    let checkOut: Date
    let guestCount: Int
    var roomCount = 1
    var allowedKinds = Set(AccommodationKind.allCases)
    var maximumTotal: Money?

    func validated() throws -> Self {
        guard !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              checkOut > checkIn, (1...20).contains(guestCount), (1...10).contains(roomCount),
              !allowedKinds.isEmpty, maximumTotal.map({ $0.amount >= 0 && !$0.currency.isEmpty }) ?? true else {
            throw HotelSearchError.invalidRequest
        }
        return self
    }
}

protocol HotelProvider: Sendable {
    var providerID: String { get }
    func search(_ request: HotelSearchRequest) async throws -> [HotelOffer]
}

struct HotelProviderFailure: Equatable, Sendable {
    let providerID: String
    let reason: String
}

enum HotelCoverageState: String, Equatable, Sendable { case complete, partial, failed }

struct HotelSearchResponse: Equatable, Sendable {
    let offers: [HotelOffer]
    let failures: [HotelProviderFailure]
    let coverage: HotelCoverageState
}

enum HotelBookingHandoffState: String, Equatable, Sendable { case destinationPrepared }

struct HotelBookingHandoff: Equatable, Sendable {
    let offerID: String
    let destination: URL
    let state: HotelBookingHandoffState
}

enum HotelSearchError: Error, Equatable, Sendable {
    case invalidRequest, noProviders, noUsableOffers, unverifiedBookingDestination
}

actor HotelSearchEngine {
    private let providers: [any HotelProvider]
    private let timeout: Duration
    private let maximumEvidenceAge: TimeInterval

    init(providers: [any HotelProvider], maximumProviders: Int = 6,
         timeout: Duration = .seconds(5), maximumEvidenceAge: TimeInterval = 10 * 60) {
        self.providers = Array(providers.prefix(max(1, maximumProviders)))
        self.timeout = timeout
        self.maximumEvidenceAge = maximumEvidenceAge
    }

    func search(_ input: HotelSearchRequest, now: Date = .now) async throws -> HotelSearchResponse {
        let request = try input.validated()
        guard !providers.isEmpty, maximumEvidenceAge > 0 else { throw HotelSearchError.noProviders }
        let providers = self.providers, timeout = self.timeout, maximumAge = maximumEvidenceAge
        var offers: [HotelOffer] = [], failures: [HotelProviderFailure] = []

        await withTaskGroup(of: HotelProviderResult.self) { group in
            for provider in providers {
                group.addTask { await Self.fetch(provider, request: request, timeout: timeout) }
            }
            for await result in group {
                switch result {
                case let .success(providerID, values):
                    offers.append(contentsOf: values.filter {
                        Self.isUsable($0, providerID: providerID, request: request, now: now, maximumAge: maximumAge)
                    })
                case let .failure(providerID, reason):
                    failures.append(.init(providerID: providerID, reason: reason))
                }
            }
        }
        try Task.checkCancellation()
        let ranked = Self.rank(offers, request: request, now: now, maximumAge: maximumAge)
        guard !ranked.isEmpty || !failures.isEmpty else { throw HotelSearchError.noUsableOffers }
        let coverage: HotelCoverageState = failures.isEmpty ? .complete : (ranked.isEmpty ? .failed : .partial)
        return .init(offers: ranked, failures: failures.sorted { $0.providerID < $1.providerID }, coverage: coverage)
    }

    func bookingHandoff(for offer: HotelOffer, now: Date = .now) throws -> HotelBookingHandoff {
        guard offer.availability.state.isVerifiedAvailable,
              let source = offer.availability.source, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let observedAt = offer.availability.observedAt,
              Self.isFresh(observedAt, now: now, maximumAge: maximumEvidenceAge),
              offer.exactBookingURL.scheme?.lowercased() == "https",
              offer.exactBookingURL.host != nil, !offer.exactBookingURL.path.isEmpty,
              offer.exactBookingURL.path != "/" else { throw HotelSearchError.unverifiedBookingDestination }
        return .init(offerID: offer.id, destination: offer.exactBookingURL, state: .destinationPrepared)
    }

    private static func fetch(_ provider: any HotelProvider, request: HotelSearchRequest,
                              timeout: Duration) async -> HotelProviderResult {
        do {
            let offers = try await withThrowingTaskGroup(of: [HotelOffer].self) { group in
                group.addTask { try await provider.search(request) }
                group.addTask { try await Task.sleep(for: timeout); throw HotelProviderError.timeout }
                guard let first = try await group.next() else { throw HotelProviderError.empty }
                group.cancelAll()
                return first
            }
            return .success(provider.providerID, offers)
        } catch is CancellationError {
            return .failure(provider.providerID, "cancelled")
        } catch HotelProviderError.timeout {
            return .failure(provider.providerID, "timeout")
        } catch {
            return .failure(provider.providerID, "provider_error")
        }
    }

    private static func isUsable(_ offer: HotelOffer, providerID: String, request: HotelSearchRequest,
                                 now: Date, maximumAge: TimeInterval) -> Bool {
        guard offer.providerID == providerID, !offer.id.isEmpty, !offer.providerOfferID.isEmpty,
              !offer.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              request.allowedKinds.contains(offer.kind), offer.stay.start == request.checkIn,
              offer.stay.end == request.checkOut, offer.quotedGuestCount == request.guestCount,
              offer.quotedRoomCount == request.roomCount, offer.availability.state != .unavailable,
              offer.exactBookingURL.scheme?.lowercased() == "https", offer.exactBookingURL.host != nil else { return false }
        if let maximum = request.maximumTotal {
            guard let total = offer.price.knownTotal, offer.price.includesMandatoryFees,
                  total.currency == maximum.currency, total.amount <= maximum.amount,
                  let observedAt = offer.price.observedAt,
                  isFresh(observedAt, now: now, maximumAge: maximumAge) else { return false }
        }
        return true
    }

    private static func rank(_ offers: [HotelOffer], request: HotelSearchRequest,
                             now: Date, maximumAge: TimeInterval) -> [HotelOffer] {
        offers.enumerated().sorted { left, right in
            let leftVerified = verifiedScore(left.element, now: now, maximumAge: maximumAge)
            let rightVerified = verifiedScore(right.element, now: now, maximumAge: maximumAge)
            if leftVerified != rightVerified { return leftVerified > rightVerified }
            if let currency = request.maximumTotal?.currency,
               let leftTotal = comparableTotal(left.element, currency: currency, now: now, maximumAge: maximumAge),
               let rightTotal = comparableTotal(right.element, currency: currency, now: now, maximumAge: maximumAge),
               leftTotal != rightTotal { return leftTotal < rightTotal }
            return left.offset < right.offset
        }.map(\.element)
    }

    private static func verifiedScore(_ offer: HotelOffer, now: Date, maximumAge: TimeInterval) -> Int {
        guard offer.availability.state.isVerifiedAvailable,
              let source = offer.availability.source, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let observedAt = offer.availability.observedAt,
              isFresh(observedAt, now: now, maximumAge: maximumAge) else { return 0 }
        return offer.availability.state == .liveConfirmed ? 2 : 1
    }

    private static func comparableTotal(_ offer: HotelOffer, currency: String, now: Date,
                                        maximumAge: TimeInterval) -> Decimal? {
        guard let total = offer.price.knownTotal, total.currency == currency,
              offer.price.includesMandatoryFees, let observedAt = offer.price.observedAt,
              isFresh(observedAt, now: now, maximumAge: maximumAge) else { return nil }
        return total.amount
    }

    private static func isFresh(_ date: Date, now: Date, maximumAge: TimeInterval) -> Bool {
        let age = now.timeIntervalSince(date)
        return age >= -60 && age <= maximumAge
    }
}

private enum HotelProviderError: Error { case timeout, empty }
private enum HotelProviderResult: Sendable {
    case success(String, [HotelOffer])
    case failure(String, String)
}
