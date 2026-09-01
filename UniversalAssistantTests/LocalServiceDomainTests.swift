import Foundation
import Testing
@testable import UniversalAssistant

private func servicePlace(phone: String? = nil, website: URL? = nil) -> Place {
    .init(id: "tow", providerID: "map", name: "Tow", category: .tow, latitude: 50.45, longitude: 30.52,
          phone: phone, officialWebsite: website, source: "map", timestamp: .now, verification: .providerReturned)
}

@Suite("Local service domain") struct LocalServiceDomainTests {
    @Test func towRequestRequiresSafeValidatedLocation() throws {
        let command = LocalCommandEngine().parse("Потрібен евакуатор")
        #expect(command.intent == .serviceSearch)
        #expect(command.entities["serviceCategory"] == "towTruck")
        let sample = LocationSample(latitude: 50.45, longitude: 30.52, horizontalAccuracy: 20,
                                    timestamp: .now, speed: 0, course: 0, source: .device)
        let location = ValidatedLocation(sample: sample, quality: .good,
                                         isSafeForLocationActions: true, manualLabel: nil)
        let query = try LocalServiceRequest(command: command, location: location).placeQuery()
        #expect(query.category == .tow)
        #expect(query.limit == 12)
    }

    @Test func directOrderRequiresVerifiedAvailabilityAndExactURL() throws {
        let planner = LocalServiceHandoffPlanner()
        let exact = URL(string: "https://tow.example/orders/new?tow=1")!
        let verified = LocalServiceOffer(place: servicePlace(phone: "+380441234567"),
                                         availability: .verifiedAvailable(source: "provider", timestamp: .now),
                                         quotedPrice: .init(amount: 1200, currency: "UAH"), exactBookingURL: exact)
        #expect(try planner.handoff(for: verified) == .init(kind: .directOrder, destination: exact, claimsAvailability: true))

        let unverified = LocalServiceOffer(place: verified.place, availability: .unverified, exactBookingURL: exact)
        #expect(try planner.handoff(for: unverified).kind == .phone)
        #expect(try planner.handoff(for: unverified).claimsAvailability == false)
    }

    @Test func fallbackOrderIsPhoneThenOfficialPageThenNavigation() throws {
        let planner = LocalServiceHandoffPlanner()
        let site = URL(string: "https://tow.example/contact/tow")!
        #expect(try planner.handoff(for: .init(place: servicePlace(phone: "+380441234567", website: site))).kind == .phone)
        #expect(try planner.handoff(for: .init(place: servicePlace(website: site))).kind == .officialWebsite)
        #expect(try planner.handoff(for: .init(place: servicePlace())).kind == .navigation)
    }

    @Test func unverifiedAvailabilityNeverCarriesPriceClaimIntoHandoff() throws {
        let offer = LocalServiceOffer(place: servicePlace(), availability: .unverified,
                                      quotedPrice: .init(amount: 1, currency: "UAH"))
        let handoff = try LocalServiceHandoffPlanner().handoff(for: offer)
        #expect(!handoff.claimsAvailability)
        #expect(handoff.kind == .navigation)
    }
}
