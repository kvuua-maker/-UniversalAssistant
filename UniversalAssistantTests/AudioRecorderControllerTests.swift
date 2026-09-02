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

    @Test func noRecordingCannotPlayShareRenameOrDelete() {
        let controller = AudioRecorderController(backend: RecorderBackendSpy(), directory: FileManager.default.temporaryDirectory)
        #expect(throws: AudioRecorderError.noRecording) { try controller.play() }
        #expect(throws: AudioRecorderError.noRecording) { try controller.shareURL() }
        #expect(throws: AudioRecorderError.invalidState) { try controller.rename(to: "Name") }
        #expect(throws: AudioRecorderError.noRecording) { try controller.delete() }
    }
}
