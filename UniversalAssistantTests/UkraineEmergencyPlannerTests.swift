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
}
