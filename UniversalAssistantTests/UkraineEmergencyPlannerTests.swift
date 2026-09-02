import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Ukraine emergency handoff")
struct UkraineEmergencyPlannerTests {
    private let planner = UkraineEmergencyPlanner()

    @Test func everyOfficialNumberUsesExactVisiblePhoneHandoff() throws {
        for service in UkraineEmergencyService.allCases {
            let plan = planner.plan(service: service, regionCode: "UA")
            #expect(plan.state == .readyForUserCall)
            #expect(plan.destination?.absoluteString == "tel:\(service.rawValue)")
            #expect(!plan.claimsDispatch)
            #expect(!plan.claimsLocationShared)
        }
    }

    @Test func v1NeverAppliesUkraineNumbersOutsideUkraine() {
        let plan = planner.plan(service: .ambulance, regionCode: "DE")
        #expect(plan.state == .unavailableOutsideUkraine)
        #expect(plan.destination == nil)
    }

    @Test func validatedLocationCanBeDisplayedAndExplicitlySharedWithoutDispatchClaim() throws {
        let now = Date(), provenance = ContextProvenance(source: "CoreLocation", objectID: "fix",
            observedAt: now.addingTimeInterval(-1), expiresAt: now.addingTimeInterval(60))
        let value = try EmergencyLocationPresenter().presentation(
            location: .init(latitude: 50.45, longitude: 30.52, horizontalAccuracyMeters: 12, provenance: provenance),
            address: "Kyiv", now: now)
        #expect(value.bestAvailableAddress == "Kyiv")
        #expect(value.shareText.contains("±12 m"))
        #expect(value.mapURL.scheme == "https")
        #expect(!value.claimsAutomaticTransmission)
    }

    @Test func staleOrInvalidLocationCannotBeShownAsCurrent() {
        let now = Date(), provenance = ContextProvenance(source: "CoreLocation", objectID: "old",
            observedAt: now.addingTimeInterval(-120), expiresAt: now.addingTimeInterval(-1))
        #expect(throws: EmergencyLocationError.invalidOrStaleLocation) {
            try EmergencyLocationPresenter().presentation(
                location: .init(latitude: 50, longitude: 30, horizontalAccuracyMeters: 10, provenance: provenance),
                address: nil, now: now)
        }
    }
}
