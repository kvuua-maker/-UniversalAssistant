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
        #expect(planner.plan(.startTimer(seconds: 60, label: nil)).mechanism == .alarmKit)
        #expect(planner.plan(.createAlarm(hour: 7, minute: 30, label: nil)).mechanism == .alarmKit)
        #expect(planner.plan(.startTimer(seconds: 0, label: nil)).completion == .unsupported)
        #expect(planner.plan(.createAlarm(hour: 25, minute: 0, label: nil)).completion == .unsupported)
    }

    @Test func timerAndAlarmLabelsSurviveCanonicalParsing() {
        let engine = LocalCommandEngine()
        let timer = engine.parse("Створи таймер чай на 75 секунд")
        #expect(timer.intent == .deviceAction)
        #expect(timer.entities["system_action"] == "timer")
        #expect(timer.entities["duration_seconds"] == "75")
        #expect(timer.entities["label"] == "чай")
        let alarm = engine.parse("Установи будильник на 06:40 ранкова пробіжка")
        #expect(alarm.intent == .deviceAction)
        #expect(alarm.entities["system_action"] == "alarm")
        #expect(alarm.entities["hour"] == "06")
        #expect(alarm.entities["minute"] == "40")
        #expect(alarm.entities["label"] == "ранкова пробіжка")
    }

    @Test func spokenDurationAndUnseenAlarmTimeConvergeOnDistinctSystemActions() {
        let engine = LocalCommandEngine()
        let timer = engine.parse("Запусти таймер для настою на одну хвилину")
        #expect(timer.intent == .deviceAction)
        #expect(timer.entities["system_action"] == "timer")
        #expect(timer.entities["duration_seconds"] == "60")
        let alarm = engine.parse("Встанови будильник на 05:47 ранній виїзд")
        #expect(alarm.intent == .deviceAction)
        #expect(alarm.entities["system_action"] == "alarm")
        #expect(alarm.entities["hour"] == "05")
        #expect(alarm.entities["minute"] == "47")
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

    @Test func batteryAndStorageSemanticVariantsRemainLocalSystemActions() {
        let engine = LocalCommandEngine()
        for phrase in [
            "Скільки заряду лишилося на телефоні?",
            "Покажи відсоток батареї",
            "Сколько заряда осталось на телефоне?",
            "Show the battery percentage"
        ] {
            let command = engine.parse(phrase)
            #expect(command.intent == .deviceAction)
            #expect(command.entities["system_action"] == "battery")
        }

        let storage = engine.parse("Скільки вільного місця залишилося на iPhone?")
        #expect(storage.intent == .deviceAction)
        #expect(storage.entities["system_action"] == "storage")
    }
}
