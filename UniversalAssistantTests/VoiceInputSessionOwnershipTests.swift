import AVFoundation
import Testing
@testable import UniversalAssistant

private actor VoiceAuthorizationGate {
    private var waiters: [CheckedContinuation<Bool, Never>] = []

    func wait() async -> Bool {
        await withCheckedContinuation { waiters.append($0) }
    }

    var count: Int { waiters.count }

    func resume(at index: Int, granted: Bool) {
        waiters.remove(at: index).resume(returning: granted)
    }
}

@MainActor
private final class IdleVoiceCaptureBackend: VoiceAudioCaptureBackend {
    private(set) var stopCount = 0
    func configureSession() throws {}
    func installTap(_ receive: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {}
    func startEngine() throws {}
    func stop() { stopCount += 1 }
}

@MainActor
struct VoiceInputSessionOwnershipTests {
    @Test func supersededPermissionContinuationCannotPublishState() async {
        let gate = VoiceAuthorizationGate()
        let capture = IdleVoiceCaptureBackend()
        let controller = VoiceInputController(captureBackend: capture, authorization: { await gate.wait() })
        var deniedEvents = 0
        controller.setEventHandler { event in
            if event == .state(.denied) { deniedEvents += 1 }
        }

        let first = Task { @MainActor in await controller.start(locale: Locale(identifier: "uk-UA")) }
        await waitForCount(1, gate: gate)
        let second = Task { @MainActor in await controller.start(locale: Locale(identifier: "uk-UA")) }
        await waitForCount(2, gate: gate)

        await gate.resume(at: 1, granted: false)
        await second.value
        #expect(controller.state == .denied)
        #expect(deniedEvents == 1)

        await gate.resume(at: 0, granted: false)
        await first.value
        #expect(controller.state == .denied)
        #expect(deniedEvents == 1)
    }

    @Test func explicitStopOwnsStateAfterPendingAuthorizationReturns() async {
        let gate = VoiceAuthorizationGate()
        let capture = IdleVoiceCaptureBackend()
        let controller = VoiceInputController(captureBackend: capture, authorization: { await gate.wait() })
        var deniedEvents = 0
        controller.setEventHandler { event in
            if event == .state(.denied) { deniedEvents += 1 }
        }

        let pending = Task { @MainActor in await controller.start() }
        await waitForCount(1, gate: gate)
        controller.stop(reason: .userPressedStop)
        await gate.resume(at: 0, granted: false)
        await pending.value

        #expect(controller.state == .idle)
        #expect(deniedEvents == 0)
    }

    @Test func audioInterruptionInvalidatesPendingSessionAndSuppressesLateAuthorization() async {
        let gate = VoiceAuthorizationGate()
        let capture = IdleVoiceCaptureBackend()
        let controller = VoiceInputController(captureBackend: capture, authorization: { await gate.wait() })
        let pending = Task { @MainActor in await controller.start() }
        await waitForCount(1, gate: gate)

        controller.handleAudioInterruptionBegan()
        #expect(controller.state == .idle)
        await gate.resume(at: 0, granted: true)
        await pending.value

        #expect(controller.state == .idle)
        #expect(capture.stopCount == 2)
    }

    @Test func sceneTransitionInvalidatesPendingVoiceSession() async {
        let gate = VoiceAuthorizationGate()
        let capture = IdleVoiceCaptureBackend()
        let controller = VoiceInputController(captureBackend: capture, authorization: { await gate.wait() })
        let model = AssistantViewModel(voiceInput: controller)
        model.toggleListening()
        await waitForCount(1, gate: gate)

        model.handleSceneBecameInactive()
        await gate.resume(at: 0, granted: true)
        await Task.yield()

        #expect(controller.state == .idle)
        #expect(!model.isListening)
    }

    @Test func harmlessRouteChangeDoesNotCancelPermissionOrCreateSecondSession() async {
        let gate = VoiceAuthorizationGate()
        let capture = IdleVoiceCaptureBackend()
        let controller = VoiceInputController(captureBackend: capture, authorization: { await gate.wait() })
        let pending = Task { @MainActor in await controller.start() }
        await waitForCount(1, gate: gate)
        controller.handleAudioRouteChanged(.init(
            reasonRawValue: AVAudioSession.RouteChangeReason.categoryChange.rawValue,
            reasonName: "categoryChange", previousInputs: [], previousOutputs: [],
            currentInputs: ["BuiltInMic"], currentOutputs: [], inputAvailable: true
        ))
        #expect(controller.state == .requestingPermission)
        #expect(await gate.count == 1)
        controller.stop(reason: .externalRequest)
        await gate.resume(at: 0, granted: true)
        await pending.value
        #expect(controller.state == .idle)
    }

    private func waitForCount(_ expected: Int, gate: VoiceAuthorizationGate) async {
        for _ in 0..<100 {
            if await gate.count == expected { return }
            await Task.yield()
        }
        Issue.record("Authorization continuation was not installed")
    }
}
