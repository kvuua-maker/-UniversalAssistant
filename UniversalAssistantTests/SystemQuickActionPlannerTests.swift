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

    @Test func documentedPublicDeviceActionsUseConcreteMechanisms() {
        #expect(planner.plan(.flashlight(enabled: true)).mechanism == .avFoundationTorch)
        #expect(planner.plan(.batteryLevel).mechanism == .uiDeviceRead)
        #expect(planner.plan(.freeStorage).mechanism == .fileSystemRead)
        #expect(planner.plan(.copyToClipboard("текст")).mechanism == .pasteboardWrite)
    }

    @Test @MainActor func productionBoundaryExecutesInjectedPublicAction() async throws {
        let command = LocalCommandEngine().parse("Покажи заряд батареї у відсотках")
        let executor = ProductionCanonicalCapabilityExecutor(publicDeviceExecute: { action in
            #expect(action == .batteryLevel)
            return "Заряд батареї: 73%"
        }, personalSearchSources: [])
        guard case let .result(result) = try await executor.execute(command) else { Issue.record("Expected local result"); return }
        #expect(result.primaryAnswer == "Заряд батареї: 73%")
    }
}
