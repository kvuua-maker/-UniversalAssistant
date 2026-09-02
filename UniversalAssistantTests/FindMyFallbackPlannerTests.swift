import Testing
@testable import UniversalAssistant

@Suite("Find My compliant fallback") struct FindMyFallbackPlannerTests {
    @Test func neverClaimsAnotherPersonsLocation() throws {
        let result = try FindMyFallbackPlanner().plan(personLabel: "Дитина", deviceHasFindMy: true)
        #expect(result.kind == .openSystemAppManually)
        #expect(result.claimsLocation == false)
        #expect(result.personLabel == "Дитина")
    }
    @Test func absentSystemAppIsTruthfullyUnavailable() throws {
        #expect(try FindMyFallbackPlanner().plan(personLabel: nil, deviceHasFindMy: false).kind == .unavailable)
    }
    @Test func blankPersonIsRejected() {
        #expect(throws: FindMyFallbackError.invalidRequest) { try FindMyFallbackPlanner().plan(personLabel: "  ", deviceHasFindMy: true) }
    }
}
