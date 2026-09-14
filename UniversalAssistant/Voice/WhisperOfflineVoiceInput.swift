import AVFoundation
import Foundation
import Observation
import UIKit
import whisper

enum WhisperOfflineVoiceConfiguration {
    static let implementationVersion = "whisper.cpp-v1.9.4-927cfce34f31707e17f2bff35c349632fb9e2c3a"
    static let modelName = "ggml-small-q5_1"
    static let modelExtension = "bin"
    static let expectedModelByteCount: Int64 = 190_085_487
    static let expectedModelSHA256 = "ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb"
    static let sampleRate: Double = 16_000
    static let channelCount: AVAudioChannelCount = 1
    static let bitDepth = 16
    static let language = "uk"
    static let task = "transcribe"
    static let maximumPromptEntries = 80
    static let requiresNetwork = false
    static let usesAppleSpeech = false
    static let automaticallySubmits = false

    static func modelURL(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: modelName, withExtension: modelExtension, subdirectory: "Models")
            ?? bundle.url(forResource: modelName, withExtension: modelExtension)
    }
}

enum WhisperOfflineVoiceError: Error, Equatable {
    case microphoneUnavailable
    case recordingFailed
    case emptyAudio
    case invalidWaveFormat
    case modelMissing
    case modelLoadFailed
    case transcriptionFailed(Int32)
    case cancelled
}

struct WhisperRecordingArtifact: Sendable {
    let url: URL
    let duration: TimeInterval
}

@MainActor
protocol WhisperAudioRecording: AnyObject {
    var isRecording: Bool { get }
    var currentTime: TimeInterval { get }
    func start(at url: URL) throws
    func updateMeters()
    var averagePower: Float { get }
    func finish() -> WhisperRecordingArtifact?
    func cancel()
}

@MainActor
final class AppleWhisperAudioRecorder: NSObject, WhisperAudioRecording {
    private var recorder: AVAudioRecorder?
    private var destination: URL?

    var isRecording: Bool { recorder?.isRecording == true }
    var currentTime: TimeInterval { recorder?.currentTime ?? 0 }
    var averagePower: Float { recorder?.averagePower(forChannel: 0) ?? -160 }

    static var recordingSettings: [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: WhisperOfflineVoiceConfiguration.sampleRate,
            AVNumberOfChannelsKey: Int(WhisperOfflineVoiceConfiguration.channelCount),
            AVLinearPCMBitDepthKey: WhisperOfflineVoiceConfiguration.bitDepth,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
    }

    func start(at url: URL) throws {
        cancel()
        guard AVAudioSession.sharedInstance().isInputAvailable else {
            throw WhisperOfflineVoiceError.microphoneUnavailable
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetoothHFP])
        try session.setPreferredSampleRate(WhisperOfflineVoiceConfiguration.sampleRate)
        try session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        try? FileManager.default.removeItem(at: url)
        let recorder = try AVAudioRecorder(url: url, settings: Self.recordingSettings)
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record() else {
            throw WhisperOfflineVoiceError.recordingFailed
        }
        self.recorder = recorder
        destination = url
        LocalVoiceDiagnosticReport.shared.record(
            "whisper_audio_recording_started",
            "sample_rate=16000 channels=1 input=pcm16"
        )
    }

    func updateMeters() { recorder?.updateMeters() }

    func finish() -> WhisperRecordingArtifact? {
        guard let recorder, let destination else { return nil }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        self.destination = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard duration > 0,
              (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 > 44 else {
            try? FileManager.default.removeItem(at: destination)
            return nil
        }
        return .init(url: destination, duration: duration)
    }

    func cancel() {
        recorder?.stop()
        recorder = nil
        if let destination { try? FileManager.default.removeItem(at: destination) }
        destination = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

final class WhisperCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() { lock.withLock { cancelled = true } }
    var isCancelled: Bool { lock.withLock { cancelled } }
}

protocol WhisperOfflineTranscribing: Sendable {
    func transcribe(audioURL: URL, promptEntries: [String], cancellation: WhisperCancellationToken) async throws -> String
    func releaseModel() async
}

private final class WhisperContextBox: @unchecked Sendable {
    let pointer: OpaquePointer

    init(_ pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        whisper_free(pointer)
    }
}

actor WhisperTranscriptionEngine: WhisperOfflineTranscribing {
    private let modelURL: URL?
    private var context: WhisperContextBox?

    init(modelURL: URL? = WhisperOfflineVoiceConfiguration.modelURL()) {
        self.modelURL = modelURL
    }

    func transcribe(
        audioURL: URL,
        promptEntries: [String],
        cancellation: WhisperCancellationToken
    ) async throws -> String {
        guard !cancellation.isCancelled else { throw WhisperOfflineVoiceError.cancelled }
        let samples = try WhisperWaveFile.samples(from: audioURL)
        guard samples.count >= Int(WhisperOfflineVoiceConfiguration.sampleRate / 10),
              Self.hasAudibleSignal(samples) else {
            throw WhisperOfflineVoiceError.emptyAudio
        }
        let context = try loadContext()
        let prompt = WhisperPromptBuilder.prompt(
            dynamicEntries: promptEntries,
            canonicalEntries: VoiceRecognitionRequestConfiguration.canonicalWhisperVocabulary
        )
        var parameters = whisper_full_default_params(WHISPER_SAMPLING_BEAM_SEARCH)
        parameters.print_realtime = false
        parameters.print_progress = false
        parameters.print_timestamps = false
        parameters.print_special = false
        parameters.translate = false
        parameters.no_context = true
        parameters.single_segment = false
        parameters.suppress_blank = true
        parameters.n_threads = Int32(max(1, min(4, ProcessInfo.processInfo.processorCount - 2)))
        parameters.beam_search.beam_size = 5
        parameters.abort_callback = { userData in
            guard let userData else { return false }
            return Unmanaged<WhisperCancellationToken>.fromOpaque(userData).takeUnretainedValue().isCancelled
        }
        parameters.abort_callback_user_data = Unmanaged.passUnretained(cancellation).toOpaque()

        let status: Int32 = samples.withUnsafeBufferPointer { sampleBuffer in
            WhisperOfflineVoiceConfiguration.language.withCString { languagePointer in
                parameters.language = languagePointer
                return prompt.withCString { promptPointer in
                    parameters.initial_prompt = prompt.isEmpty ? nil : promptPointer
                    return whisper_full(
                        context,
                        parameters,
                        sampleBuffer.baseAddress,
                        Int32(sampleBuffer.count)
                    )
                }
            }
        }
        guard !cancellation.isCancelled else { throw WhisperOfflineVoiceError.cancelled }
        guard status == 0 else { throw WhisperOfflineVoiceError.transcriptionFailed(status) }

        let count = whisper_full_n_segments(context)
        var rawTranscript = ""
        if count > 0 {
            for index in 0..<count {
                rawTranscript += String(cString: whisper_full_get_segment_text(context, index))
            }
        }
        return VoiceTranscriptStabilizer.normalizedForDisplay(rawTranscript)
    }

    func releaseModel() async {
        context = nil
    }

    func validateModelLoad() throws {
        _ = try loadContext()
    }

    private func loadContext() throws -> OpaquePointer {
        if let context { return context.pointer }
        guard let modelURL,
              modelURL.lastPathComponent == "\(WhisperOfflineVoiceConfiguration.modelName).\(WhisperOfflineVoiceConfiguration.modelExtension)",
              FileManager.default.fileExists(atPath: modelURL.path) else {
            throw WhisperOfflineVoiceError.modelMissing
        }
        var parameters = whisper_context_default_params()
#if targetEnvironment(simulator)
        parameters.use_gpu = false
#else
        parameters.use_gpu = true
        parameters.flash_attn = true
#endif
        guard let loaded = whisper_init_from_file_with_params(modelURL.path, parameters) else {
            throw WhisperOfflineVoiceError.modelLoadFailed
        }
        context = WhisperContextBox(loaded)
        return loaded
    }

    private static func hasAudibleSignal(_ samples: [Float]) -> Bool {
        let peak = samples.reduce(Float.zero) { max($0, abs($1)) }
        return peak >= 0.002
    }
}

private final class NotificationObserverToken: @unchecked Sendable {
    private var token: NSObjectProtocol?

    init(_ token: NSObjectProtocol) {
        self.token = token
    }

    deinit {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

enum WhisperWaveFile {
    static func samples(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard abs(format.sampleRate - WhisperOfflineVoiceConfiguration.sampleRate) < 0.5,
              format.channelCount == WhisperOfflineVoiceConfiguration.channelCount,
              file.length > 0,
              file.length <= AVAudioFramePosition(UInt32.max) else {
            throw WhisperOfflineVoiceError.invalidWaveFormat
        }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else { throw WhisperOfflineVoiceError.invalidWaveFormat }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?.pointee else {
            throw WhisperOfflineVoiceError.invalidWaveFormat
        }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }
}

enum WhisperPromptBuilder {
    static func prompt(dynamicEntries: [String], canonicalEntries: [String]) -> String {
        prompt(from: canonicalEntries + dynamicEntries)
    }

    static func prompt(from entries: [String]) -> String {
        var seen: Set<String> = []
        var values: [String] = []
        for raw in entries where values.count < WhisperOfflineVoiceConfiguration.maximumPromptEntries {
            let value = raw.precomposedStringWithCanonicalMapping
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty,
                  value.split(whereSeparator: \.isWhitespace).count <= 4 else { continue }
            let key = value.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "uk-UA")
            )
            guard seen.insert(key).inserted else { continue }
            values.append(value)
        }
        return values.joined(separator: ", ")
    }
}

@MainActor
@Observable
final class WhisperVoiceInputController: VoiceInputControlling {
    let engineIdentifier = "whisper.cpp"
    private(set) var state: VoiceInputState = .idle
    private(set) var transcript = ""

    private let recorder: any WhisperAudioRecording
    private let transcriber: any WhisperOfflineTranscribing
    private let authorization: @Sendable () async -> Bool
    private let contextualVocabulary: @Sendable () async -> [String]
    private let modelAvailable: @Sendable () -> Bool
    private let temporaryDirectory: URL
    private var activeSessionID: UUID?
    private var transcriptionID: UUID?
    private var transcriptionTask: Task<Void, Never>?
    private var endpointTask: Task<Void, Never>?
    private var cancellation: WhisperCancellationToken?
    private var activeTranscriptionURL: URL?
    @ObservationIgnored private var eventHandler: (@MainActor @Sendable (VoiceInputEvent) -> Void)?
    @ObservationIgnored private var audioEvents: AudioSessionEventMonitor?
    @ObservationIgnored private var memoryWarningObserver: NotificationObserverToken?

    init(
        recorder: (any WhisperAudioRecording)? = nil,
        transcriber: (any WhisperOfflineTranscribing)? = nil,
        authorization: (@Sendable () async -> Bool)? = nil,
        contextualVocabulary: @escaping @Sendable () async -> [String] = { [] },
        modelAvailable: @escaping @Sendable () -> Bool = { WhisperOfflineVoiceConfiguration.modelURL() != nil },
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.recorder = recorder ?? AppleWhisperAudioRecorder()
        self.transcriber = transcriber ?? WhisperTranscriptionEngine()
        self.authorization = authorization ?? Self.microphoneAuthorizationGranted
        self.contextualVocabulary = contextualVocabulary
        self.modelAvailable = modelAvailable
        self.temporaryDirectory = temporaryDirectory
        audioEvents = AudioSessionEventMonitor(
            onInterruption: { [weak self] in self?.handleInterruption() },
            onRouteChange: { [weak self] evidence in self?.handleRouteChange(evidence) }
        )
        memoryWarningObserver = NotificationObserverToken(NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.releaseModelForMemoryPressure() }
        })
    }

    func start(locale _: Locale = Locale(identifier: "uk-UA")) async {
        cancelCurrentSession(reason: .sessionRestart)
        let sessionID = UUID()
        activeSessionID = sessionID
        transcript = ""
        LocalVoiceDiagnosticReport.shared.reset()
        LocalVoiceDiagnosticReport.shared.record(
            "voice_engine_selected",
            "provider=whisper language=uk mechanism=offline"
        )
        setState(.requestingPermission)
        guard await authorization() else {
            guard activeSessionID == sessionID else { return }
            activeSessionID = nil
            setState(.denied)
            return
        }
        guard activeSessionID == sessionID else { return }
        guard modelAvailable() else {
            activeSessionID = nil
            LocalVoiceDiagnosticReport.shared.record("whisper_model_missing", "status=error")
            setState(.unavailable)
            return
        }
        let destination = temporaryDirectory.appendingPathComponent("ua-whisper-\(sessionID.uuidString).wav")
        do {
            try recorder.start(at: destination)
            guard activeSessionID == sessionID else {
                recorder.cancel()
                return
            }
            setState(.listening)
            startEndpointMonitoring(sessionID: sessionID)
        } catch {
            guard activeSessionID == sessionID else { return }
            activeSessionID = nil
            recorder.cancel()
            LocalVoiceDiagnosticReport.shared.record(
                "whisper_recording_failed",
                "error_type=\(String(describing: type(of: error)))"
            )
            setState(.failed)
        }
    }

    func stop(reason: VoiceStopReason = .externalRequest) {
        switch reason {
        case .userPressedStop, .recognitionFinal:
            finishAndTranscribe(reason: reason)
        default:
            cancelCurrentSession(reason: reason)
        }
    }

    func setEventHandler(_ handler: @escaping @MainActor @Sendable (VoiceInputEvent) -> Void) {
        eventHandler = handler
    }

    private func finishAndTranscribe(reason: VoiceStopReason) {
        guard let sessionID = activeSessionID, state == .listening else { return }
        activeSessionID = nil
        endpointTask?.cancel()
        endpointTask = nil
        guard let artifact = recorder.finish() else {
            LocalVoiceDiagnosticReport.shared.record("whisper_audio_empty", "status=error")
            setState(.failed)
            return
        }
        LocalVoiceDiagnosticReport.shared.record(
            "whisper_audio_recording_finished",
            "duration=\(Int((artifact.duration * 1000).rounded())) reason=\(reason.rawValue)"
        )
        let token = WhisperCancellationToken()
        cancellation = token
        transcriptionID = sessionID
        activeTranscriptionURL = artifact.url
        setState(.transcribing)
        let transcriber = transcriber
        let vocabularyProvider = contextualVocabulary
        transcriptionTask = Task { @MainActor [weak self] in
            defer {
                try? FileManager.default.removeItem(at: artifact.url)
                if self?.activeTranscriptionURL == artifact.url {
                    self?.activeTranscriptionURL = nil
                }
            }
            do {
                let vocabulary = await vocabularyProvider()
                let rawTranscript = try await transcriber.transcribe(
                    audioURL: artifact.url,
                    promptEntries: vocabulary,
                    cancellation: token
                )
                guard let self,
                      self.transcriptionID == sessionID,
                      !token.isCancelled else { return }
                let finalTranscript = VoiceTranscriptStabilizer.normalizedForDisplay(rawTranscript)
                guard !finalTranscript.isEmpty else { throw WhisperOfflineVoiceError.emptyAudio }
                self.transcript = finalTranscript
                LocalVoiceDiagnosticReport.shared.recordSpeechTranscript(finalTranscript, isFinal: true)
                LocalVoiceDiagnosticReport.shared.record(
                    "whisper_transcription_finished",
                    "language=uk length=\(finalTranscript.count) status=success"
                )
                let evidence = VoiceRecognitionEvidence(
                    primaryTranscript: finalTranscript,
                    alternativeTranscripts: [],
                    segmentAlternativeCount: 0,
                    averageSegmentConfidence: nil
                )
                self.eventHandler?(.recognitionEvidence(evidence))
                self.eventHandler?(.transcript(finalTranscript, isFinal: true))
                self.transcriptionID = nil
                self.cancellation = nil
                self.transcriptionTask = nil
                self.setState(.idle)
            } catch {
                guard let self, self.transcriptionID == sessionID else { return }
                self.transcriptionID = nil
                self.cancellation = nil
                self.transcriptionTask = nil
                LocalVoiceDiagnosticReport.shared.record(
                    "whisper_transcription_failed",
                    "error_type=\(String(describing: type(of: error))) status=error"
                )
                self.setState(error as? WhisperOfflineVoiceError == .modelMissing ? .unavailable : .failed)
            }
        }
    }

    private func cancelCurrentSession(reason: VoiceStopReason) {
        activeSessionID = nil
        transcriptionID = nil
        endpointTask?.cancel()
        endpointTask = nil
        cancellation?.cancel()
        cancellation = nil
        transcriptionTask?.cancel()
        transcriptionTask = nil
        recorder.cancel()
        if let activeTranscriptionURL { try? FileManager.default.removeItem(at: activeTranscriptionURL) }
        activeTranscriptionURL = nil
        LocalVoiceDiagnosticReport.shared.record("whisper_session_cancelled", "reason=\(reason.rawValue)")
        if state == .listening || state == .requestingPermission || state == .transcribing {
            setState(.idle)
        }
    }

    private func startEndpointMonitoring(sessionID: UUID) {
        endpointTask?.cancel()
        endpointTask = Task { @MainActor [weak self] in
            var heardSpeech = false
            var quietSince: ContinuousClock.Instant?
            let clock = ContinuousClock()
            while let self,
                  self.activeSessionID == sessionID,
                  self.recorder.isRecording {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                self.recorder.updateMeters()
                let power = self.recorder.averagePower
                if power > -46 {
                    heardSpeech = true
                    quietSince = nil
                } else if heardSpeech {
                    quietSince = quietSince ?? clock.now
                    if let quietSince, quietSince.duration(to: clock.now) >= .milliseconds(1_800) {
                        self.finishAndTranscribe(reason: .recognitionFinal)
                        return
                    }
                }
                if self.recorder.currentTime >= 45 {
                    self.finishAndTranscribe(reason: .recognitionFinal)
                    return
                }
            }
        }
    }

    private func handleInterruption() {
        LocalVoiceDiagnosticReport.shared.record("audio_interruption", "state=began provider=whisper")
        cancelCurrentSession(reason: .audioInterruption)
        setState(.failed)
    }

    private func handleRouteChange(_ evidence: AudioRouteChangeEvidence) {
        LocalVoiceDiagnosticReport.shared.record("route_change", evidence.diagnosticDescription)
        if evidence.requiresVoiceCaptureStop {
            cancelCurrentSession(reason: .routeChange)
            setState(.failed)
        }
    }

    private func releaseModelForMemoryPressure() {
        cancellation?.cancel()
        Task { await transcriber.releaseModel() }
    }

    private func setState(_ newState: VoiceInputState) {
        state = newState
        LocalVoiceDiagnosticReport.shared.record("state_transition", "state=\(String(describing: newState))")
        eventHandler?(.state(newState))
    }

    private nonisolated static func microphoneAuthorizationGranted() async -> Bool {
        LocalVoiceDiagnosticReport.shared.record(
            "microphone_permission_before",
            "state=\(String(describing: AVAudioApplication.shared.recordPermission))"
        )
        let granted = await AVAudioApplication.requestRecordPermission()
        LocalVoiceDiagnosticReport.shared.record("microphone_permission", "granted=\(granted)")
        return granted
    }
}
