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

    @Test func noRecordingCannotPlayShareRenameOrDelete() {
        let controller = AudioRecorderController(backend: RecorderBackendSpy(), directory: FileManager.default.temporaryDirectory)
        #expect(throws: AudioRecorderError.noRecording) { try controller.play() }
        #expect(throws: AudioRecorderError.noRecording) { try controller.shareURL() }
        #expect(throws: AudioRecorderError.invalidState) { try controller.rename(to: "Name") }
        #expect(throws: AudioRecorderError.noRecording) { try controller.delete() }
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

@MainActor
struct VoiceAudioCaptureLifecycleTests {
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
