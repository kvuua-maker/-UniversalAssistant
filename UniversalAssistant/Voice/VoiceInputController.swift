import AVFoundation
import Observation
import OSLog
import Speech

enum VoiceInputState: Equatable, Sendable { case idle, requestingPermission, listening, denied, unavailable, failed }

enum VoiceInputEvent: Equatable, Sendable {
    case state(VoiceInputState)
    case transcript(String, isFinal: Bool)
}

enum VoiceStopReason: String, Sendable {
    case sessionRestart, externalRequest, userPressedStop, voiceDisabled, sceneInactive
    case recognitionFinal, recognitionError, audioInterruption, routeChange, startFailure
}

private enum VoiceDiagnostic {
    static let logger = Logger(subsystem: "com.universalassistant.app", category: "VoicePipeline")
}

final class LocalVoiceDiagnosticReport: @unchecked Sendable {
    static let shared = LocalVoiceDiagnosticReport()
    private let lock = NSLock()
    private var entries: [String] = []

    func reset() {
        lock.lock(); entries = []; lock.unlock()
    }

    func record(_ marker: String, _ details: String = "") {
        lock.lock()
        let sequence = entries.count + 1
        entries.append("\(sequence). \(marker)\(details.isEmpty ? "" : " | \(details)")")
        if entries.count > 200 { entries.removeFirst(entries.count - 200) }
        lock.unlock()
        VoiceDiagnostic.logger.notice("\(marker, privacy: .public) \(details, privacy: .public)")
    }

    func snapshot() -> String {
        lock.lock(); defer { lock.unlock() }
        return (["UniversalAssistant Local Voice Diagnostic", "No audio or transcript content recorded."] + entries).joined(separator: "\n")
    }
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
            LocalVoiceDiagnosticReport.shared.record("audio_buffer_received", "count=\(current) frames=\(buffer.frameLength)")
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
        LocalVoiceDiagnosticReport.shared.record("audio_session_activated", "input=\(input) sample_rate=\(session.sampleRate)")
    }

    func installTap(_ receive: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw VoiceAudioCaptureError.invalidInputFormat
        }
        LocalVoiceDiagnosticReport.shared.record("audio_tap_installed", "sample_rate=\(format.sampleRate) channels=\(format.channelCount)")
        input.installTap(onBus: 0, bufferSize: 1_024, format: format,
                         block: Self.makeTapHandler(receive))
        tapInstalled = true
    }

    nonisolated static func makeTapHandler(
        _ receive: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) -> AVAudioNodeTapBlock {
        let counter = VoiceBufferDiagnosticCounter()
        return { buffer, _ in
            counter.record(buffer)
            receive(buffer)
        }
    }

    func startEngine() throws {
        audioEngine.prepare()
        try audioEngine.start()
        LocalVoiceDiagnosticReport.shared.record("audio_engine_started", "running=\(audioEngine.isRunning)")
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
    private let lock = NSLock()
    private var appendedCount = 0

    init(_ request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request.append(buffer)
        lock.lock(); appendedCount += 1; let current = appendedCount; lock.unlock()
        if current == 1 || current.isMultiple(of: 100) {
            LocalVoiceDiagnosticReport.shared.record("buffer_appended", "count=\(current)")
        }
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
    @ObservationIgnored private var partialResultCount = 0
    @ObservationIgnored private var finalResultCount = 0

    init(captureBackend: (any VoiceAudioCaptureBackend)? = nil) {
        capture = VoiceAudioCaptureLifecycle(backend: captureBackend ?? AppleVoiceAudioCaptureBackend())
        audioEvents = AudioSessionEventMonitor(
            onInterruption: { [weak self] in self?.handleAudioInterruptionBegan() },
            onRouteChange: { [weak self] evidence in self?.handleAudioRouteChanged(evidence) })
    }

    func start(locale: Locale = .current) async {
        stop(reason: .sessionRestart)
        LocalVoiceDiagnosticReport.shared.reset()
        recognitionCallbackCount = 0
        partialResultCount = 0
        finalResultCount = 0
        LocalVoiceDiagnosticReport.shared.record("start_listening_invoked")
        setState(.requestingPermission)
        guard await Self.authorizationGranted() else { setState(.denied); return }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else { setState(.unavailable); return }
        LocalVoiceDiagnosticReport.shared.record("recognizer_ready", "locale=\(locale.identifier) available=\(recognizer.isAvailable)")
        self.recognizer = recognizer
        let request = SFSpeechAudioBufferRecognitionRequest(); request.shouldReportPartialResults = true
        LocalVoiceDiagnosticReport.shared.record("recognition_request_created", "partial_results=true")
        self.request = request
        let requestSink = VoiceRecognitionRequestSink(request)
        do {
            try capture.start { buffer in requestSink.append(buffer) }
            setState(.listening)
            task = recognizer.recognitionTask(with: request, resultHandler: Self.makeRecognitionHandler(owner: self))
            LocalVoiceDiagnosticReport.shared.record("recognition_task_created")
        } catch {
            LocalVoiceDiagnosticReport.shared.record("voice_start_failed", "error_type=\(String(describing: type(of: error)))")
            stop(reason: .startFailure); setState(.failed)
        }
    }

    func stop(reason: VoiceStopReason = .externalRequest) {
        LocalVoiceDiagnosticReport.shared.record("stop_invoked", "reason=\(reason.rawValue)")
        let hadTask = task != nil
        let hadRequest = request != nil
        task?.cancel(); task = nil; request?.endAudio(); request = nil
        LocalVoiceDiagnosticReport.shared.record("recognition_task_cancelled", "reason=\(reason.rawValue) had_task=\(hadTask)")
        LocalVoiceDiagnosticReport.shared.record("end_audio_called", "reason=\(reason.rawValue) had_request=\(hadRequest)")
        capture.stop()
        if state == .listening || state == .requestingPermission { setState(.idle) }
    }

    func setEventHandler(_ handler: @escaping @MainActor @Sendable (VoiceInputEvent) -> Void) {
        eventHandler = handler
    }

    private func setState(_ newState: VoiceInputState) {
        state = newState
        LocalVoiceDiagnosticReport.shared.record("state_transition", "state=\(String(describing: newState))")
        eventHandler?(.state(newState))
    }

    private func receiveRecognition(transcript: String?, isFinal: Bool, hasError: Bool, errorDomain: String, errorCode: Int) {
        recognitionCallbackCount += 1
        if transcript != nil {
            if isFinal { finalResultCount += 1 } else { partialResultCount += 1 }
        }
        LocalVoiceDiagnosticReport.shared.record("recognition_callback", "count=\(recognitionCallbackCount) has_text=\(transcript != nil) final=\(isFinal) error_domain=\(errorDomain) error_code=\(errorCode) partial_count=\(partialResultCount) final_count=\(finalResultCount)")
        if let transcript {
            self.transcript = transcript
            eventHandler?(.transcript(transcript, isFinal: isFinal))
            LocalVoiceDiagnosticReport.shared.record(isFinal ? "final_transcript" : "partial_transcript", "length=\(transcript.count)")
            LocalVoiceDiagnosticReport.shared.record("transcript_delivered_to_ui", "length=\(transcript.count) final=\(isFinal)")
        }
        if hasError { stop(reason: .recognitionError) }
        else if isFinal {
            LocalVoiceDiagnosticReport.shared.record("recognition_task_finished", "reason=final_result")
            stop(reason: .recognitionFinal)
        }
    }

    func handleAudioInterruptionBegan() { stop(reason: .audioInterruption) }
    func handleAudioRouteChanged() { if state == .listening { stop(reason: .routeChange) } }

    func handleAudioRouteChanged(_ evidence: AudioRouteChangeEvidence) {
        LocalVoiceDiagnosticReport.shared.record("route_change", evidence.diagnosticDescription)
        if evidence.requiresVoiceCaptureStop {
            handleAudioRouteChanged()
        } else {
            LocalVoiceDiagnosticReport.shared.record("route_change_ignored", "reason=\(evidence.reasonName) input_preserved=true")
        }
    }

    nonisolated static func awaitSpeechAuthorization(
        _ request: @escaping @Sendable (@escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void) -> Void
    ) async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            request { status in continuation.resume(returning: status) }
        }
    }

    private nonisolated static func authorizationGranted() async -> Bool {
        LocalVoiceDiagnosticReport.shared.record("speech_permission_before", "state=\(String(describing: SFSpeechRecognizer.authorizationStatus()))")
        let speech = await awaitSpeechAuthorization { completion in
            SFSpeechRecognizer.requestAuthorization(completion)
        }
        LocalVoiceDiagnosticReport.shared.record("speech_permission_after", "state=\(String(describing: speech))")
        guard speech == .authorized else { return false }
        LocalVoiceDiagnosticReport.shared.record("microphone_permission_before", "state=\(String(describing: AVAudioApplication.shared.recordPermission))")
        let microphone = await AVAudioApplication.requestRecordPermission()
        LocalVoiceDiagnosticReport.shared.record("microphone_permission", "granted=\(microphone)")
        return microphone
    }

    private nonisolated static func makeRecognitionHandler(
        owner: VoiceInputController
    ) -> @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { [weak owner] result, error in
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal == true
            let hasError = error != nil
            let nsError = error as NSError?
            let errorDomain = nsError?.domain ?? "none"
            let errorCode = nsError?.code ?? 0
            Task { @MainActor [weak owner] in
                owner?.receiveRecognition(transcript: transcript, isFinal: isFinal, hasError: hasError, errorDomain: errorDomain, errorCode: errorCode)
            }
        }
    }
}
