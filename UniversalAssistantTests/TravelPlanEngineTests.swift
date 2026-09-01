import Foundation
import Testing
@testable import UniversalAssistant

private func travelJourney(
    _ id: String, now: Date, arrival: Date, mode: IntercityTravelMode = .rail,
    price: Decimal? = 1_000, availability: VerifiedServiceAvailability = .available,
    evidence: TravelEvidenceLevel = .providerConfirmed, observedAt: Date? = nil
) -> TravelJourney {
    .init(id: id, providerID: "provider", mode: mode, origin: "Kyiv", destination: "Lviv",
          departure: now.addingTimeInterval(3_600), arrival: arrival,
          price: price.map { .init(amount: $0, currency: "UAH") }, transfers: 0,
          availability: availability, evidenceLevel: evidence, observedAt: observedAt ?? now)
}

private func travelRequest(_ now: Date, budget: Decimal? = nil) -> TravelPlanRequest {
    .init(origin: "Kyiv", destination: "Lviv", departureNotBefore: now,
          arrivalNotAfter: now.addingTimeInterval(28_800),
          maximumTotal: budget.map { .init(amount: $0, currency: "UAH") })
}

@Suite("Truthful travel plan core") struct TravelPlanEngineTests {
    @Test func arrivalDeadlineAndModesAreHardConstraints() throws {
        let now = Date(), request = travelRequest(now)
        let plans = try TravelPlanEngine().plan(request: request, journeys: [
            travelJourney("late", now: now, arrival: now.addingTimeInterval(30_000)),
            travelJourney("flight", now: now, arrival: now.addingTimeInterval(7_000), mode: .flight),
            travelJourney("rail", now: now, arrival: now.addingTimeInterval(8_000))
        ], now: now)
        #expect(plans.map(\.id) == ["flight", "rail"])
    }

    @Test func scheduledAvailabilityCannotSatisfyVerifiedRequest() throws {
        let now = Date()
        var request = travelRequest(now)
        request.requiresVerifiedAvailability = true
        #expect(throws: TravelPlanError.noFeasibleJourney) {
            try TravelPlanEngine().plan(request: request, journeys: [
                travelJourney("schedule", now: now, arrival: now.addingTimeInterval(8_000), evidence: .scheduled)
            ], now: now)
        }
    }

    @Test func missingSupportingContextIsTruthfulPartialCoverage() throws {
        let now = Date()
        var request = travelRequest(now)
        request.needsAccommodation = true
        let plan = try #require(TravelPlanEngine().plan(
            request: request,
            journeys: [travelJourney("rail", now: now, arrival: now.addingTimeInterval(8_000))],
            now: now
        ).first)
        #expect(plan.coverage == .partial)
        #expect(plan.missingContext == ["origin_access", "destination_access", "accommodation", "weather"])
    }

    @Test func totalBudgetRequiresKnownComparableJourneyAndHotelPrices() throws {
        let now = Date()
        var request = travelRequest(now, budget: 2_500)
        request.needsAccommodation = true
        let hotelRequest = HotelSearchRequest(location: "Lviv", checkIn: now.addingTimeInterval(86_400),
                                               checkOut: now.addingTimeInterval(172_800), guestCount: 1)
        let pricedHotel = HotelOffer(
            id: "hotel", providerID: "hotel-provider", providerOfferID: "offer", kind: .hotel,
            name: "Verified Hotel", locationLabel: "Lviv",
            stay: .init(start: hotelRequest.checkIn, end: hotelRequest.checkOut),
            quotedGuestCount: 1, quotedRoomCount: 1,
            price: .init(knownTotal: .init(amount: 1_200, currency: "UAH"), nightlyRate: nil,
                         includesMandatoryFees: true, observedAt: now),
            availability: .init(state: .providerConfirmed, source: "hotel-provider", observedAt: now),
            exactBookingURL: URL(string: "https://hotel.example/offer")!, fetchedAt: now
        )
        let plans = try TravelPlanEngine().plan(
            request: request,
            journeys: [travelJourney("rail", now: now, arrival: now.addingTimeInterval(8_000))],
            hotels: [pricedHotel], now: now
        )
        #expect(plans.first?.knownTotal?.amount == 2_200)
    }

    @Test func staleJourneyEvidenceIsNeverPresentedAsCurrent() throws {
        let now = Date()
        #expect(throws: TravelPlanError.noFeasibleJourney) {
            try TravelPlanEngine().plan(request: travelRequest(now), journeys: [
                travelJourney("stale", now: now, arrival: now.addingTimeInterval(8_000),
                              observedAt: now.addingTimeInterval(-1_000))
            ], now: now)
        }
    }

    @Test func requiredAccommodationCannotDisappearFromBudget() throws {
        let now = Date()
        var request = travelRequest(now, budget: 2_500)
        request.needsAccommodation = true
        #expect(throws: TravelPlanError.noFeasibleJourney) {
            try TravelPlanEngine().plan(
                request: request,
                journeys: [travelJourney("rail", now: now, arrival: now.addingTimeInterval(8_000))],
                hotels: [], now: now
            )
        }
    }
}
