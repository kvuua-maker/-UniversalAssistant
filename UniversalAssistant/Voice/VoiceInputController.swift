import AVFoundation
import Observation
import Speech

enum VoiceInputState: Equatable, Sendable { case idle, requestingPermission, listening, denied, unavailable, failed }

enum VoiceAudioCaptureError: Error, Equatable {
    case invalidInputFormat
}

@MainActor
protocol VoiceAudioCaptureBackend: AnyObject {
    func configureSession() throws
    func installTap(_ receive: @escaping (AVAudioPCMBuffer) -> Void) throws
    func startEngine() throws
    func stop()
}

@MainActor
final class AppleVoiceAudioCaptureBackend: VoiceAudioCaptureBackend {
    private let audioEngine = AVAudioEngine()
    private var tapInstalled = false

    func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetoothHFP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    func installTap(_ receive: @escaping (AVAudioPCMBuffer) -> Void) throws {
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw VoiceAudioCaptureError.invalidInputFormat
        }
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in receive(buffer) }
        tapInstalled = true
    }

    func startEngine() throws {
        audioEngine.prepare()
        try audioEngine.start()
    }

    func stop() {
        if audioEngine.isRunning { audioEngine.stop() }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

@MainActor
struct VoiceAudioCaptureLifecycle {
    let backend: any VoiceAudioCaptureBackend

    func start(receive: @escaping (AVAudioPCMBuffer) -> Void) throws {
        do {
            try backend.configureSession()
            try backend.installTap(receive)
            try backend.startEngine()
        } catch {
            backend.stop()
            throw error
        }
    }

    func stop() { backend.stop() }
}

@MainActor
@Observable
final class VoiceInputController {
    private(set) var state: VoiceInputState = .idle
    private(set) var transcript = ""
    private let capture: VoiceAudioCaptureLifecycle
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var audioEvents: AudioSessionEventMonitor?

    init(captureBackend: (any VoiceAudioCaptureBackend)? = nil) {
        capture = VoiceAudioCaptureLifecycle(backend: captureBackend ?? AppleVoiceAudioCaptureBackend())
        audioEvents = AudioSessionEventMonitor(
            onInterruption: { [weak self] in self?.handleAudioInterruptionBegan() },
            onRouteChange: { [weak self] in self?.handleAudioRouteChanged() })
    }

    func start(locale: Locale = .current) async {
        stop()
        state = .requestingPermission
        guard await authorizationGranted() else { state = .denied; return }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else { state = .unavailable; return }
        self.recognizer = recognizer
        let request = SFSpeechAudioBufferRecognitionRequest(); request.shouldReportPartialResults = true
        self.request = request
        do {
            try capture.start { [weak request] buffer in request?.append(buffer) }
            state = .listening
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    if let result { self?.transcript = result.bestTranscription.formattedString }
                    if error != nil || result?.isFinal == true { self?.stop() }
                }
            }
        } catch { stop(); state = .failed }
    }

    func stop() {
        task?.cancel(); task = nil; request?.endAudio(); request = nil
        capture.stop()
        if state == .listening || state == .requestingPermission { state = .idle }
    }

    func handleAudioInterruptionBegan() { stop() }
    func handleAudioRouteChanged() { if state == .listening { stop() } }

    private func authorizationGranted() async -> Bool {
        let speech = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) } }
        guard speech == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
