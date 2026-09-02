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

    @Test func timerAndAlarmNeverPretendToCompleteWithoutPublicAPI() {
        #expect(planner.plan(.startTimer(seconds: 60)).completion == .unsupported)
        #expect(planner.plan(.createAlarm(hour: 7, minute: 30)).completion == .unsupported)
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
