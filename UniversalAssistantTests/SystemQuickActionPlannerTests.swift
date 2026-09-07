import Foundation
import Testing
@testable import UniversalAssistant

@Suite("System-first quick actions")
struct SystemQuickActionPlannerTests {
    private let planner = SystemQuickActionPlanner()

    @Test func cameraUsesPublicVisibleCaptureWithoutClaimingPhotoTaken() {
        let plan = planner.plan(.takePhoto)
        #expect(plan.mechanism == .avFoundationCapture)
        #expect(plan.completion == .readyForUserInteraction)
        #expect(plan.destination == nil)
    }

    @Test func compoundCameraTaskPreservesRequestedContinuation() {
        let plan = planner.plan(.captureThen(.translateSelection))
        #expect(plan.completion == .requiresCapturedAsset)
        #expect(plan.continuation == .translateSelection)
    }

    @Test func timerAndAlarmUsePublicAlarmKitPlansAndRejectInvalidValues() {
        #expect(planner.plan(.startTimer(seconds: 60)).mechanism == .alarmKit)
        #expect(planner.plan(.createAlarm(hour: 7, minute: 30)).mechanism == .alarmKit)
        #expect(planner.plan(.startTimer(seconds: 0)).completion == .unsupported)
        #expect(planner.plan(.createAlarm(hour: 25, minute: 0)).completion == .unsupported)
    }

    @Test func onlyBoundedVerifiedAppDestinationsArePrepared() throws {
        let telegram = try #require(URL(string: "tg://resolve?domain=telegram"))
        #expect(planner.plan(.openApp(verifiedURL: telegram)).mechanism == .verifiedApplicationURL)
        let unsafe = try #require(URL(string: "javascript:alert(1)"))
        #expect(planner.plan(.openApp(verifiedURL: unsafe)).completion == .unsupported)
    }

    @Test func filesUsesSystemDocumentPicker() {
        #expect(planner.plan(.openFiles).mechanism == .documentPicker)
    }
}
