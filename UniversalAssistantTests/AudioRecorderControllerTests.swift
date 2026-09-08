import AVFoundation
import Foundation
import Testing
@testable import UniversalAssistant

@MainActor
final class RecorderBackendSpy: AudioRecordingBackend {
    var isRecording = false
    var events: [String] = []
    func start(at url: URL) throws -> Bool { events.append("start"); isRecording = true; try Data("audio".utf8).write(to: url); return true }
    func pause() { events.append("pause"); isRecording = false }
    func resume() -> Bool { events.append("resume"); isRecording = true; return true }
    func stop() { events.append("stop"); isRecording = false }
    func play(url: URL) { events.append("play") }
    func stopPlayback() { events.append("stopPlayback") }
}

@MainActor
struct AudioRecorderControllerTests {
    @Test func pauseResumeStopStateMachine() async throws {
        let backend = RecorderBackendSpy()
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let controller = AudioRecorderController(backend: backend, directory: directory, permission: { true })
        await controller.start()
        #expect(controller.state == .recording)
        controller.pause(); #expect(controller.state == .paused)
        controller.resume(); #expect(controller.state == .recording)
        controller.stop(); #expect(controller.state == .stopped)
        try controller.play(); #expect(controller.state == .playing)
        controller.stopPlayback(); #expect(controller.state == .stopped)
        #expect(backend.events == ["start", "pause", "resume", "stop", "play", "stopPlayback"])
        #expect(try controller.shareURL().pathExtension == "m4a")
        try controller.rename(to: "Interview")
        #expect(try controller.shareURL().lastPathComponent == "Interview.m4a")
        try controller.delete(); #expect(controller.state == .idle)
    }

    @Test func deniedPermissionNeverStartsBackend() async {
        let backend = RecorderBackendSpy()
        let controller = AudioRecorderController(backend: backend, permission: { false })
        await controller.start()
        #expect(controller.state == .denied)
        #expect(backend.events.isEmpty)
    }

    @Test func typedCommandsDriveTheRealControllerStateMachine() async {
        let backend = RecorderBackendSpy()
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let controller = AudioRecorderController(backend: backend, directory: directory, permission: { true })
        await controller.execute(.start); #expect(controller.state == .recording)
        await controller.execute(.pause); #expect(controller.state == .paused)
        await controller.execute(.resume); #expect(controller.state == .recording)
        await controller.execute(.stop); #expect(controller.state == .stopped)
    }

    @Test func viewModelRoutesRecorderIntentToExistingController() async {
        let backend = RecorderBackendSpy()
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let controller = AudioRecorderController(backend: backend, directory: directory, permission: { true })
        let model = AssistantViewModel(recorder: controller)
        model.input = "Запиши аудіо"
        model.submit()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(controller.state == .recording)
        #expect(backend.events == ["start"])
    }

    @Test func unsupportedParsedIntentDoesNotMasqueradeAsExecuted() async {
        let model = AssistantViewModel()
        model.input = "Увімкни ліхтарик"
        model.submit()
        for _ in 0..<500 {
            if case .failure = model.resultState { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        guard case .failure = model.resultState else {
            Issue.record("Expected truthful unavailable result")
            return
        }
    }

    @Test func noRecordingCannotPlayShareRenameOrDelete() {
        let controller = AudioRecorderController(backend: RecorderBackendSpy(), directory: FileManager.default.temporaryDirectory)
        #expect(throws: AudioRecorderError.noRecording) { try controller.play() }
        #expect(throws: AudioRecorderError.noRecording) { try controller.shareURL() }
        #expect(throws: AudioRecorderError.invalidState) { try controller.rename(to: "Name") }
        #expect(throws: AudioRecorderError.noRecording) { try controller.delete() }
    }

    @Test func finalizedRecordingRecoversAfterControllerRecreation() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let first = AudioRecorderController(backend: RecorderBackendSpy(), directory: directory, permission: { true })
        await first.start(); first.stop()
        let finalized = try first.shareURL()
        let recovered = AudioRecorderController(backend: RecorderBackendSpy(), directory: directory, permission: { true })
        #expect(recovered.state == .stopped)
        #expect(try recovered.shareURL() == finalized)
    }

    @Test func openVoiceMemosIsNeverInternalRecording() async {
        let backend = RecorderBackendSpy()
        let recorder = AudioRecorderController(backend: backend, directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString), permission: { true })
        let command = LocalCommandEngine().parse("Відкрий голосові записи")
        #expect(command.intent == .open)
        let executor = ProductionCanonicalCapabilityExecutor(recorder: recorder, personalSearchSources: [])
        await #expect(throws: CanonicalCapabilityExecutionError.unavailable("no_verified_public_app_mechanism")) { try await executor.execute(command) }
        #expect(backend.events.isEmpty)
    }

    @Test func homeLifecycleFinalizesPublishesAndRecoversAudioFile() async throws {
        let backend = RecorderBackendSpy()
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let recorder = AudioRecorderController(backend: backend, directory: directory, permission: { true })
        let model = AssistantViewModel(recorder: recorder)
        model.input = "Почни запис голосової нотатки"; model.submit()
        for _ in 0..<100 { if recorder.state == .recording { break }; try await Task.sleep(for: .milliseconds(10)) }
        model.input = "Заверши запис аудіо"; model.submit()
        for _ in 0..<100 { if recorder.state == .stopped { break }; try await Task.sleep(for: .milliseconds(10)) }
        guard case let .audioFile(url) = model.capabilityPresentation else { Issue.record("Expected finalized audio file presentation"); return }
        #expect(url == recorder.recordingURL)
        let reopened = AudioRecorderController(backend: RecorderBackendSpy(), directory: directory, permission: { true })
        #expect(reopened.recordingURL == url)
    }

}


@MainActor
private final class VoiceCaptureBackendSpy: VoiceAudioCaptureBackend {
    enum Failure: Error { case configured, tap, engine }
    var events: [String] = []
    var failure: Failure?

    func configureSession() throws {
        events.append("configure")
        if failure == .configured { throw Failure.configured }
    }

    func installTap(_ receive: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        events.append("installTap")
        if failure == .tap { throw Failure.tap }
    }

    func startEngine() throws {
        events.append("startEngine")
        if failure == .engine { throw Failure.engine }
    }

    func stop() { events.append("stop") }
}

private final class VoiceTapInvocation: @unchecked Sendable {
    let handler: AVAudioNodeTapBlock
    let buffer: AVAudioPCMBuffer

    init(handler: @escaping AVAudioNodeTapBlock, buffer: AVAudioPCMBuffer) {
        self.handler = handler
        self.buffer = buffer
    }

    func invoke() {
        handler(buffer, AVAudioTime(sampleTime: 0, atRate: 44_100))
    }
}

@MainActor
struct VoiceAudioCaptureLifecycleTests {
    @Test func partialResultSilenceFinishesOnce() async {
        let finalizer = VoiceEndOfSpeechFinalizer(delay: .milliseconds(50))
        var count = 0
        finalizer.receivedPartial { count += 1 }
        try? await Task.sleep(for: .milliseconds(250))
        #expect(count == 1)
    }

    @Test func newerPartialRearmsEndOfSpeechWindow() async {
        let finalizer = VoiceEndOfSpeechFinalizer(delay: .milliseconds(100))
        var count = 0
        finalizer.receivedPartial { count += 1 }
        try? await Task.sleep(for: .milliseconds(50))
        finalizer.receivedPartial { count += 1 }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(count == 0)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(count == 1)
    }

    @Test func explicitStopCancelsPendingEndOfSpeechFinalization() async {
        let finalizer = VoiceEndOfSpeechFinalizer(delay: .milliseconds(50))
        var count = 0
        finalizer.receivedPartial { count += 1 }
        finalizer.cancel()
        try? await Task.sleep(for: .milliseconds(250))
        #expect(count == 0)
    }

    @Test func realtimeTapCallbackHasNoMainActorExecutorRequirementAndDeliversBuffer() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64)!
        buffer.frameLength = 64
        let delivered = DispatchSemaphore(value: 0)
        let handler = AppleVoiceAudioCaptureBackend.makeTapHandler { _ in delivered.signal() }
        let invocation = VoiceTapInvocation(handler: handler, buffer: buffer)
        DispatchQueue.global(qos: .userInitiated).async {
            invocation.invoke()
        }
        #expect(delivered.wait(timeout: .now() + 2) == .success)
    }

    @Test func routeChangeEvidenceIncludesReasonRoutesAndInputAvailability() {
        let evidence = AudioRouteChangeEvidence(
            reasonRawValue: 3,
            reasonName: "categoryChange",
            previousInputs: ["BuiltInMic:iPhone Microphone"],
            previousOutputs: ["Speaker:iPhone Speaker"],
            currentInputs: ["BuiltInMic:iPhone Microphone"],
            currentOutputs: [],
            inputAvailable: true
        )
        #expect(evidence.diagnosticDescription.contains("reason=categoryChange(3)"))
        #expect(evidence.diagnosticDescription.contains("previous_inputs="))
        #expect(evidence.diagnosticDescription.contains("current_inputs="))
        #expect(evidence.diagnosticDescription.contains("input_available=true"))
    }

    @Test func harmlessStartupCategoryChangeKeepsRecognitionActive() {
        let evidence = AudioRouteChangeEvidence(
            reasonRawValue: AVAudioSession.RouteChangeReason.categoryChange.rawValue,
            reasonName: "categoryChange",
            previousInputs: [], previousOutputs: ["Speaker:iPhone Speaker"],
            currentInputs: ["BuiltInMic:iPhone Microphone"], currentOutputs: [],
            inputAvailable: true
        )
        #expect(!evidence.requiresVoiceCaptureStop)
    }

    @Test func genuineInputLossRequiresSafeStop() {
        let evidence = AudioRouteChangeEvidence(
            reasonRawValue: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue,
            reasonName: "oldDeviceUnavailable",
            previousInputs: ["BluetoothHFP:Headset"], previousOutputs: [],
            currentInputs: [], currentOutputs: ["Speaker:iPhone Speaker"],
            inputAvailable: false
        )
        #expect(evidence.requiresVoiceCaptureStop)
    }

    @Test func categoryChangeWithoutUsableInputStillRequiresSafeStop() {
        let evidence = AudioRouteChangeEvidence(
            reasonRawValue: AVAudioSession.RouteChangeReason.categoryChange.rawValue,
            reasonName: "categoryChange",
            previousInputs: ["BuiltInMic:iPhone Microphone"], previousOutputs: [],
            currentInputs: [], currentOutputs: ["Speaker:iPhone Speaker"],
            inputAvailable: true
        )
        #expect(evidence.requiresVoiceCaptureStop)
    }

    @Test func speechPermissionCallbackSafelyResumesFromBackgroundQueue() async {
        let status = await VoiceInputController.awaitSpeechAuthorization { completion in
            DispatchQueue.global(qos: .default).async {
                completion(.authorized)
            }
        }
        #expect(status == .authorized)
    }

    @Test func configuresAndActivatesSessionBeforeInstallingInputTap() throws {
        let backend = VoiceCaptureBackendSpy()
        let lifecycle = VoiceAudioCaptureLifecycle(backend: backend)
        try lifecycle.start { _ in }
        #expect(backend.events == ["configure", "installTap", "startEngine"])
    }

    @Test func inputFormatOrEngineFailureCleansUpInsteadOfEscapingAsProcessCrash() {
        let backend = VoiceCaptureBackendSpy()
        backend.failure = .tap
        let lifecycle = VoiceAudioCaptureLifecycle(backend: backend)
        #expect(throws: VoiceCaptureBackendSpy.Failure.tap) { try lifecycle.start { _ in } }
        #expect(backend.events == ["configure", "installTap", "stop"])
    }

    @Test func stoppingBeforeOrAfterCaptureIsIdempotentAtLifecycleBoundary() throws {
        let backend = VoiceCaptureBackendSpy()
        let lifecycle = VoiceAudioCaptureLifecycle(backend: backend)
        lifecycle.stop()
        lifecycle.stop()
        #expect(backend.events == ["stop", "stop"])
    }
}
