import Foundation
import Testing
@testable import UniversalAssistant

@MainActor
@Suite("Accessibility, audio and contextual permissions")
struct AccessibilityAudioPermissionTests {
    @Test func voicePrivacyModeKeepsTypedInteractionWorking() {
        let model = AssistantViewModel()
        model.setVoiceInputEnabled(false)
        model.input = "Покажи погоду"
        model.submit()
        #expect(!model.isListening)
        #expect(model.resultState != .idle)
    }

    @Test func permissionsAreNeverRequestedAtLaunchAndRemainContextual() {
        let policy = ContextualPermissionPolicy()
        #expect(policy.decision(for: .appLaunch) == .doNotRequest)
        #expect(policy.decision(for: .proactiveFeatureEnabled) == .notifications)
        #expect(policy.decision(for: .locationTask(.nearbySearch), reducedLocationAccuracy: true) == .locationWhenInUse)
        #expect(policy.decision(for: .locationTask(.navigation), reducedLocationAccuracy: true) == .temporaryPreciseLocation)
    }

    @Test func recorderPausesOnCallOrBluetoothRouteChange() async {
        let backend = RecorderBackendSpy()
        let controller = AudioRecorderController(backend: backend,
            directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString), permission: { true })
        await controller.start()
        controller.handleAudioInterruptionBegan()
        #expect(controller.state == .paused)
        controller.resume()
        controller.handleAudioRouteChanged()
        #expect(controller.state == .paused)
        #expect(backend.events == ["start", "pause", "resume", "pause"])
    }
}
