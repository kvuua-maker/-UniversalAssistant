import AVFoundation
import Observation
import OSLog
import Speech

enum VoiceInputState: Equatable, Sendable { case idle, requestingPermission, listening, denied, unavailable, failed }

enum VoiceInputEvent: Equatable, Sendable {
    case state(VoiceInputState)
    case transcript(String, isFinal: Bool)
}

private enum VoiceDiagnostic {
    static let logger = Logger(subsystem: "com.universalassistant.app", category: "VoicePipeline")
}

private final class VoiceBufferDiagnosticCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func record(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        count += 1
        let current = count
        lock.unlock()
        if current == 1 || current.isMultiple(of: 100) {
            VoiceDiagnostic.logger.notice("audio_buffer count=\(current, privacy: .public) frames=\(buffer.frameLength, privacy: .public)")
        }
    }
}

enum VoiceAudioCaptureError: Error, Equatable {
    case invalidInputFormat
}

@MainActor
protocol VoiceAudioCaptureBackend: AnyObject {
    func configureSession() throws
    func installTap(_ receive: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws
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
        let input = session.currentRoute.inputs.first?.portType.rawValue ?? "none"
        VoiceDiagnostic.logger.notice("audio_session_activated input=\(input, privacy: .public) sample_rate=\(session.sampleRate, privacy: .public)")
    }

    func installTap(_ receive: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw VoiceAudioCaptureError.invalidInputFormat
        }
        VoiceDiagnostic.logger.notice("audio_tap_install sample_rate=\(format.sampleRate, privacy: .public) channels=\(format.channelCount, privacy: .public)")
        let counter = VoiceBufferDiagnosticCounter()
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            counter.record(buffer)
            receive(buffer)
        }
        tapInstalled = true
    }

    func startEngine() throws {
        audioEngine.prepare()
        try audioEngine.start()
        VoiceDiagnostic.logger.notice("audio_engine_started running=\(self.audioEngine.isRunning, privacy: .public)")
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

    func start(receive: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
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

private final class VoiceRecognitionRequestSink: @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest

    init(_ request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request.append(buffer)
    }
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
    @ObservationIgnored private var eventHandler: (@MainActor @Sendable (VoiceInputEvent) -> Void)?
    @ObservationIgnored private var recognitionCallbackCount = 0

    init(captureBackend: (any VoiceAudioCaptureBackend)? = nil) {
        capture = VoiceAudioCaptureLifecycle(backend: captureBackend ?? AppleVoiceAudioCaptureBackend())
        audioEvents = AudioSessionEventMonitor(
            onInterruption: { [weak self] in self?.handleAudioInterruptionBegan() },
            onRouteChange: { [weak self] in self?.handleAudioRouteChanged() })
    }

    func start(locale: Locale = .current) async {
        stop()
        setState(.requestingPermission)
        guard await Self.authorizationGranted() else { setState(.denied); return }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else { setState(.unavailable); return }
        VoiceDiagnostic.logger.notice("recognizer_ready locale=\(locale.identifier, privacy: .public) available=\(recognizer.isAvailable, privacy: .public)")
        self.recognizer = recognizer
        let request = SFSpeechAudioBufferRecognitionRequest(); request.shouldReportPartialResults = true
        VoiceDiagnostic.logger.notice("recognition_request_created partial_results=true")
        self.request = request
        let requestSink = VoiceRecognitionRequestSink(request)
        do {
            try capture.start { buffer in requestSink.append(buffer) }
            setState(.listening)
            task = recognizer.recognitionTask(with: request, resultHandler: Self.makeRecognitionHandler(owner: self))
            VoiceDiagnostic.logger.notice("recognition_task_created")
        } catch {
            VoiceDiagnostic.logger.error("voice_start_failed error_type=\(String(describing: type(of: error)), privacy: .public)")
            stop(); setState(.failed)
        }
    }

    func stop() {
        VoiceDiagnostic.logger.notice("voice_stop_requested")
        task?.cancel(); task = nil; request?.endAudio(); request = nil
        VoiceDiagnostic.logger.notice("recognition_task_cancelled end_audio_called=true")
        capture.stop()
        if state == .listening || state == .requestingPermission { setState(.idle) }
    }

    func setEventHandler(_ handler: @escaping @MainActor @Sendable (VoiceInputEvent) -> Void) {
        eventHandler = handler
    }

    private func setState(_ newState: VoiceInputState) {
        state = newState
        eventHandler?(.state(newState))
    }

    private func receiveRecognition(transcript: String?, isFinal: Bool, hasError: Bool, errorType: String) {
        recognitionCallbackCount += 1
        VoiceDiagnostic.logger.notice("recognition_callback count=\(self.recognitionCallbackCount, privacy: .public) has_text=\(transcript != nil, privacy: .public) final=\(isFinal, privacy: .public) error_type=\(errorType, privacy: .public)")
        if let transcript {
            self.transcript = transcript
            eventHandler?(.transcript(transcript, isFinal: isFinal))
            VoiceDiagnostic.logger.notice("transcript_delivered_to_ui length=\(transcript.count, privacy: .public) final=\(isFinal, privacy: .public)")
        }
        if hasError || isFinal { stop() }
    }

    func handleAudioInterruptionBegan() { stop() }
    func handleAudioRouteChanged() { if state == .listening { stop() } }

    nonisolated static func awaitSpeechAuthorization(
        _ request: @escaping @Sendable (@escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void) -> Void
    ) async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            request { status in continuation.resume(returning: status) }
        }
    }

    private nonisolated static func authorizationGranted() async -> Bool {
        VoiceDiagnostic.logger.notice("speech_permission_before=\(String(describing: SFSpeechRecognizer.authorizationStatus()), privacy: .public)")
        let speech = await awaitSpeechAuthorization { completion in
            SFSpeechRecognizer.requestAuthorization(completion)
        }
        VoiceDiagnostic.logger.notice("speech_permission_after=\(String(describing: speech), privacy: .public)")
        guard speech == .authorized else { return false }
        let microphone = await AVAudioApplication.requestRecordPermission()
        VoiceDiagnostic.logger.notice("microphone_permission_granted=\(microphone, privacy: .public)")
        return microphone
    }

    private nonisolated static func makeRecognitionHandler(
        owner: VoiceInputController
    ) -> @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { [weak owner] result, error in
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal == true
            let hasError = error != nil
            let errorType = error.map { String(describing: type(of: $0)) } ?? "none"
            Task { @MainActor [weak owner] in
                owner?.receiveRecognition(transcript: transcript, isFinal: isFinal, hasError: hasError, errorType: errorType)
            }
        }
    }
}
