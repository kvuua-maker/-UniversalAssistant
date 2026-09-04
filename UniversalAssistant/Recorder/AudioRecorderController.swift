import AVFoundation
import Foundation
import Observation

enum AudioRecorderState: Equatable, Sendable {
    case idle, requestingPermission, recording, paused, stopped, playing, denied, failed
}

@MainActor
protocol AudioRecordingBackend: AnyObject {
    var isRecording: Bool { get }
    func start(at url: URL) throws -> Bool
    func pause()
    func resume() -> Bool
    func stop()
    func play(url: URL) throws
    func stopPlayback()
}

@MainActor
final class AppleAudioRecordingBackend: NSObject, AudioRecordingBackend, AVAudioPlayerDelegate {
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    var isRecording: Bool { recorder?.isRecording == true }

    func start(at url: URL) throws -> Bool {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        recorder = try AVAudioRecorder(url: url, settings: [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ])
        guard recorder?.prepareToRecord() == true else { return false }
        return recorder?.record() == true
    }

    func pause() { recorder?.pause() }
    func resume() -> Bool { recorder?.record() == true }
    func stop() {
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func play(url: URL) throws {
        player = try AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        guard player?.play() == true else { throw AudioRecorderError.operationFailed }
    }
    func stopPlayback() { player?.stop(); player = nil }
}

enum AudioRecorderError: Error, Equatable {
    case invalidState, noRecording, invalidName, operationFailed
}

enum AudioRecorderCommand: String, Equatable, Sendable { case start, pause, resume, stop }

@MainActor
@Observable
final class AudioRecorderController {
    private(set) var state: AudioRecorderState = .idle
    private(set) var recordingURL: URL?
    private let backend: any AudioRecordingBackend
    private let directory: URL
    private let permission: () async -> Bool
    @ObservationIgnored private var audioEvents: AudioSessionEventMonitor?

    init(
        backend: any AudioRecordingBackend = AppleAudioRecordingBackend(),
        directory: URL? = nil,
        permission: @escaping () async -> Bool = { await AVAudioApplication.requestRecordPermission() }
    ) {
        self.backend = backend
        self.directory = directory ?? Self.defaultDirectory()
        self.permission = permission
        audioEvents = AudioSessionEventMonitor(
            onInterruption: { [weak self] in self?.handleAudioInterruptionBegan() },
            onRouteChange: { [weak self] _ in self?.handleAudioRouteChanged() })
    }

    func start() async {
        guard [.idle, .stopped].contains(state) else { return }
        state = .requestingPermission
        guard await permission() else { state = .denied; return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: "Recording-\(UUID().uuidString).m4a")
            guard try backend.start(at: url) else { throw AudioRecorderError.operationFailed }
            recordingURL = url
            state = .recording
        } catch { state = .failed }
    }

    func execute(_ command: AudioRecorderCommand) async {
        switch command {
        case .start: await start()
        case .pause: pause()
        case .resume: resume()
        case .stop: stop()
        }
    }

    func pause() {
        guard state == .recording else { return }
        backend.pause(); state = .paused
    }
    func resume() {
        guard state == .paused else { return }
        state = backend.resume() ? .recording : .failed
    }
    func stop() {
        guard state == .recording || state == .paused else { return }
        backend.stop()
        if let recordingURL { try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: recordingURL.path) }
        state = .stopped
    }
    func play() throws {
        guard state == .stopped, let recordingURL else { throw AudioRecorderError.noRecording }
        try backend.play(url: recordingURL); state = .playing
    }
    func stopPlayback() {
        guard state == .playing else { return }
        backend.stopPlayback(); state = .stopped
    }
    func handleAudioInterruptionBegan() {
        if state == .recording { backend.pause(); state = .paused }
        else if state == .playing { backend.stopPlayback(); state = .stopped }
    }
    func handleAudioRouteChanged() {
        if state == .recording { backend.pause(); state = .paused }
    }
    func rename(to name: String) throws {
        guard state == .stopped, let source = recordingURL else { throw AudioRecorderError.invalidState }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.range(of: #"[/\\:]"#, options: .regularExpression) == nil else { throw AudioRecorderError.invalidName }
        let destination = directory.appending(path: trimmed).appendingPathExtension("m4a")
        try FileManager.default.moveItem(at: source, to: destination)
        recordingURL = destination
    }
    func delete() throws {
        guard state == .stopped,
              let url = recordingURL,
              url.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path else {
            throw AudioRecorderError.noRecording
        }
        try FileManager.default.removeItem(at: url)
        recordingURL = nil; state = .idle
    }
    func shareURL() throws -> URL {
        guard state == .stopped, let recordingURL else { throw AudioRecorderError.noRecording }
        return recordingURL
    }

    private static func defaultDirectory() -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        return base.appending(path: "UniversalAssistant/Recordings", directoryHint: .isDirectory)
    }
}
