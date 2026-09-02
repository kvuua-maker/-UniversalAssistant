import Foundation
import Testing
@testable import UniversalAssistant

private struct HotelProviderFixture: HotelProvider {
    let providerID: String
    let offers: [HotelOffer]
    var delay: Duration = .zero
    var fails = false

    func search(_ request: HotelSearchRequest) async throws -> [HotelOffer] {
        if delay > .zero { try await Task.sleep(for: delay) }
        if fails { throw FixtureError.failed }
        return offers
    }

    private enum FixtureError: Error { case failed }
}

private actor HotelHTTPRecorder: HotelHTTPTransport {
    var responses: [(Data, Int)]
    private(set) var requests: [URLRequest] = []
    init(_ responses: [(Data, Int)]) { self.responses = responses }
    func data(for request: URLRequest) throws -> (Data, Int) {
        requests.append(request)
        return responses.removeFirst()
    }
    func recorded() -> [URLRequest] { requests }
}

private func hotelRequest(_ now: Date, maximum: Decimal? = nil) -> HotelSearchRequest {
    .init(location: "Lviv", checkIn: now.addingTimeInterval(86_400),
          checkOut: now.addingTimeInterval(172_800), guestCount: 2,
          maximumTotal: maximum.map { .init(amount: $0, currency: "UAH") })
}

private func hotel(_ id: String, provider: String, request: HotelSearchRequest, now: Date,
                   total: Decimal? = 2_000, feesKnown: Bool = true,
                   availability: HotelAvailabilityState = .providerConfirmed,
                   observedAt: Date? = nil) -> HotelOffer {
    .init(id: id, providerID: provider, providerOfferID: "offer-\(id)", kind: .hotel,
          name: "Hotel \(id)", locationLabel: request.location,
          stay: .init(start: request.checkIn, end: request.checkOut),
          quotedGuestCount: request.guestCount, quotedRoomCount: request.roomCount,
          price: .init(knownTotal: total.map { .init(amount: $0, currency: "UAH") }, nightlyRate: nil,
                       includesMandatoryFees: feesKnown, observedAt: total == nil ? nil : (observedAt ?? now)),
          availability: .init(state: availability, source: availability == .unknown ? nil : provider,
                              observedAt: availability == .unknown ? nil : (observedAt ?? now)),
          exactBookingURL: URL(string: "https://hotels.example/offers/\(id)")!, fetchedAt: now)
}

@Suite("Truthful hotel search core") struct HotelSearchEngineTests {
    @Test func hardStayGuestAndBudgetConstraintsRejectNonComparableOffers() async throws {
        let now = Date(), request = hotelRequest(now, maximum: 2_500)
        var wrongStay = hotel("wrong-stay", provider: "p", request: request, now: now)
        wrongStay = .init(id: wrongStay.id, providerID: wrongStay.providerID,
                          providerOfferID: wrongStay.providerOfferID, kind: wrongStay.kind, name: wrongStay.name,
                          locationLabel: wrongStay.locationLabel,
                          stay: .init(start: request.checkIn, end: request.checkOut.addingTimeInterval(86_400)),
                          quotedGuestCount: 2, quotedRoomCount: 1, price: wrongStay.price,
                          availability: wrongStay.availability, exactBookingURL: wrongStay.exactBookingURL,
                          fetchedAt: now)
        let response = try await HotelSearchEngine(providers: [HotelProviderFixture(providerID: "p", offers: [
            wrongStay,
            hotel("missing-fees", provider: "p", request: request, now: now, feesKnown: false),
            hotel("too-much", provider: "p", request: request, now: now, total: 3_000),
            hotel("valid", provider: "p", request: request, now: now, total: 2_400)
        ])]).search(request, now: now)
        #expect(response.offers.map(\.id) == ["valid"])
        #expect(response.coverage == .complete)
    }

    @Test func failedProviderProducesTruthfulPartialCoverage() async throws {
        let now = Date(), request = hotelRequest(now)
        let response = try await HotelSearchEngine(providers: [
            HotelProviderFixture(providerID: "good", offers: [hotel("real", provider: "good", request: request, now: now)]),
            HotelProviderFixture(providerID: "broken", offers: [], fails: true)
        ]).search(request, now: now)
        #expect(response.offers.map(\.id) == ["real"])
        #expect(response.coverage == .partial)
        #expect(response.failures == [.init(providerID: "broken", reason: "provider_error")])
    }

    @Test func slowProviderTimesOutWithoutBlockingVerifiedResult() async throws {
        let now = Date(), request = hotelRequest(now)
        let response = try await HotelSearchEngine(providers: [
            HotelProviderFixture(providerID: "fast", offers: [hotel("fast", provider: "fast", request: request, now: now)]),
            HotelProviderFixture(providerID: "slow", offers: [], delay: .seconds(2))
        ], timeout: .milliseconds(20)).search(request, now: now)
        #expect(response.offers.map(\.id) == ["fast"])
        #expect(response.failures == [.init(providerID: "slow", reason: "timeout")])
    }

    @Test func unknownOrStaleAvailabilityCannotPrepareBookingHandoff() async throws {
        let now = Date(), request = hotelRequest(now)
        let engine = HotelSearchEngine(providers: [])
        await #expect(throws: HotelSearchError.unverifiedBookingDestination) {
            try await engine.bookingHandoff(
                for: hotel("unknown", provider: "p", request: request, now: now,
                           availability: .unknown),
                now: now
            )
        }
        await #expect(throws: HotelSearchError.unverifiedBookingDestination) {
            try await engine.bookingHandoff(
                for: hotel("stale", provider: "p", request: request, now: now,
                           observedAt: now.addingTimeInterval(-1_000)),
                now: now
            )
        }
    }

    @Test func exactVerifiedHandoffOnlyPreparesProviderDestination() async throws {
        let now = Date(), request = hotelRequest(now)
        let engine = HotelSearchEngine(providers: [])
        let handoff = try await engine.bookingHandoff(for: hotel("verified", provider: "p", request: request, now: now), now: now)
        #expect(handoff.state == .destinationPrepared)
        #expect(handoff.destination.path == "/offers/verified")
    }

    @Test func officialHTTPProviderInjectsCredentialAndParsesOnlyItsOffers() async throws {
        let now = Date(), request = hotelRequest(now)
        let valid = hotel("valid", provider: "official", request: request, now: now)
        let foreign = hotel("foreign", provider: "other", request: request, now: now)
        let transport = HotelHTTPRecorder([(try JSONEncoder().encode([valid, foreign]), 200)])
        let provider = try OfficialHotelHTTPProvider(providerID: "official",
            searchURL: URL(string: "https://hotels.example/search")!, bearerToken: "secret", transport: transport)
        #expect(try await provider.search(request).map(\.id) == ["valid"])
        let recorded = await transport.recorded()
        #expect(recorded.first?.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(recorded.first?.timeoutInterval == 8)
    }

    @Test func officialHTTPProviderRejectsCredentialAndRateLimitFailures() async throws {
        let endpoint = URL(string: "https://hotels.example/search")!
        #expect(throws: HotelHTTPError.missingCredential) {
            try OfficialHotelHTTPProvider(providerID: "official", searchURL: endpoint, bearerToken: " ")
        }
        let provider = try OfficialHotelHTTPProvider(providerID: "official", searchURL: endpoint,
            bearerToken: "token", transport: HotelHTTPRecorder([(Data("{}".utf8), 429)]))
        await #expect(throws: HotelHTTPError.rateLimited) { try await provider.search(hotelRequest(.now)) }
    }
}
