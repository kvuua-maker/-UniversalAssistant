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

enum WhisperMicrophonePermissionState: String, Equatable, Sendable {
    case undetermined = "UNDETERMINED"
    case authorized = "AUTHORIZED"
    case denied = "DENIED"
    case restricted = "RESTRICTED"
}

enum WhisperVoiceLifecyclePhase: String, Equatable, Sendable {
    case idle = "IDLE"
    case requestingPermission = "REQUESTING_PERMISSION"
    case preparing = "PREPARING"
    case recording = "RECORDING"
    case stopping = "STOPPING"
    case converting = "CONVERTING"
    case transcribing = "TRANSCRIBING"
    case result = "RESULT"
}

enum WhisperVoiceStartStage: String, Equatable, Sendable {
    case micPermissionDenied = "MIC_PERMISSION_DENIED"
    case audioSessionConfigFailed = "AUDIO_SESSION_CONFIG_FAILED"
    case audioSessionActivateFailed = "AUDIO_SESSION_ACTIVATE_FAILED"
    case noInput = "NO_INPUT"
    case fileCreateFailed = "FILE_CREATE_FAILED"
    case recorderInitFailed = "RECORDER_INIT_FAILED"
    case prepareFailed = "PREPARE_FAILED"
    case recordFailed = "RECORD_FAILED"
    case audioRouteConflict = "AUDIO_ROUTE_CONFLICT"
    case inputFormatFailed = "INPUT_FORMAT_FAILED"
    case nativeFileOpenFailed = "NATIVE_FILE_OPEN_FAILED"
    case audioEngineStartFailed = "AUDIO_ENGINE_START_FAILED"
    case audioFileWriteFailed = "AUDIO_FILE_WRITE_FAILED"
}

struct WhisperVoiceStartFailure: Error, Equatable {
    let stage: WhisperVoiceStartStage
    let errorDomain: String
    let errorCode: Int
    let context: [String: String]

    init(stage: WhisperVoiceStartStage, underlying: Error? = nil, context: [String: String] = [:]) {
        self.stage = stage
        let error = underlying as NSError?
        errorDomain = error?.domain ?? "none"
        errorCode = error?.code ?? 0
        self.context = context
    }

    var diagnosticDetails: String {
        var attributes = context
        attributes["stage"] = stage.rawValue
        attributes["internal_code"] = stage.rawValue
        attributes["error_domain"] = errorDomain
        attributes["error_code"] = String(errorCode)
        attributes["status"] = "error"
        if errorDomain == NSOSStatusErrorDomain {
            attributes["osstatus"] = String(errorCode)
        }
        return attributes.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
    }
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
    private final class NativeAudioSink: @unchecked Sendable {
        private let lock = NSLock()
        private var file: AVAudioFile?
        private var writtenFrames: AVAudioFramePosition = 0
        private var storedError: Error?
        private var power: Float = -160
        let sampleRate: Double

        init(file: AVAudioFile, sampleRate: Double) {
            self.file = file
            self.sampleRate = sampleRate
        }

        func append(_ buffer: AVAudioPCMBuffer) {
            guard buffer.frameLength > 0 else { return }
            lock.lock()
            defer { lock.unlock() }
            guard storedError == nil, let file else { return }
            do {
                try file.write(from: buffer)
                writtenFrames += AVAudioFramePosition(buffer.frameLength)
                power = Self.averagePower(buffer)
            } catch {
                storedError = error
            }
        }

        var duration: TimeInterval {
            lock.withLock { sampleRate > 0 ? Double(writtenFrames) / sampleRate : 0 }
        }

        var averagePower: Float { lock.withLock { power } }
        var error: Error? { lock.withLock { storedError } }

        func close() {
            lock.withLock { file = nil }
        }

        private static func averagePower(_ buffer: AVAudioPCMBuffer) -> Float {
            guard let channels = buffer.floatChannelData else { return -160 }
            let frameCount = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)
            guard frameCount > 0, channelCount > 0 else { return -160 }
            var sum: Float = 0
            for channel in 0..<channelCount {
                let samples = UnsafeBufferPointer(start: channels[channel], count: frameCount)
                for sample in samples { sum += sample * sample }
            }
            let rms = sqrt(sum / Float(frameCount * channelCount))
            return rms > 0 ? max(-160, 20 * log10(rms)) : -160
        }
    }

    private var audioEngine: AVAudioEngine?
    private var audioSink: NativeAudioSink?
    private var destination: URL?
    private var nativeDestination: URL?
    private var tapInstalled = false

    var isRecording: Bool {
        audioEngine?.isRunning == true && audioSink?.error == nil
    }
    var currentTime: TimeInterval { audioSink?.duration ?? 0 }
    var averagePower: Float { audioSink?.averagePower ?? -160 }

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

    static func nativeCaptureSettings(sampleRate: Double) -> [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: WhisperOfflineVoiceConfiguration.bitDepth,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
    }

    func start(at url: URL) throws {
        cancel()
        let session = AVAudioSession.sharedInstance()
        LocalVoiceDiagnosticReport.shared.record(
            "SESSION_CONFIG_PRE",
            "category=record mode=measurement status=begin"
        )
        do {
            try session.setCategory(
                .record,
                mode: .measurement,
                options: [.allowBluetoothHFP]
            )
            try session.setPreferredSampleRate(48_000)
            try session.setPreferredIOBufferDuration(0.02)
        } catch {
            throw WhisperVoiceStartFailure(
                stage: .audioSessionConfigFailed,
                underlying: error,
                context: Self.sessionContext(session)
            )
        }
        LocalVoiceDiagnosticReport.shared.record(
            "SESSION_CONFIG_POST",
            Self.sessionDetails(session, status: "success")
        )
        LocalVoiceDiagnosticReport.shared.record("SESSION_ACTIVE_PRE", "status=begin")
        do {
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw WhisperVoiceStartFailure(
                stage: .audioSessionActivateFailed,
                underlying: error,
                context: Self.sessionContext(session)
            )
        }
        LocalVoiceDiagnosticReport.shared.record(
            "SESSION_ACTIVE_POST",
            Self.sessionDetails(session, status: "success")
        )
        guard session.isInputAvailable, session.inputNumberOfChannels > 0 else {
            throw WhisperVoiceStartFailure(stage: .noInput, context: Self.sessionContext(session))
        }
        LocalVoiceDiagnosticReport.shared.record(
            "INPUT_ROUTE",
            Self.sessionDetails(session, status: "available")
        )
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw WhisperVoiceStartFailure(
                stage: .fileCreateFailed,
                underlying: error,
                context: ["file_name": url.lastPathComponent]
            )
        }

        let nativeURL = url.deletingPathExtension()
            .appendingPathExtension("native.caf")
        try? FileManager.default.removeItem(at: nativeURL)
        try? FileManager.default.removeItem(at: url)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw WhisperVoiceStartFailure(
                stage: .inputFormatFailed,
                context: Self.sessionContext(session).merging([
                    "actual_sample_rate": String(Int(inputFormat.sampleRate.rounded())),
                    "actual_input_channels": String(inputFormat.channelCount)
                ]) { _, new in new }
            )
        }

        let nativeFile: AVAudioFile
        do {
            nativeFile = try AVAudioFile(
                forWriting: nativeURL,
                settings: inputFormat.settings,
                commonFormat: inputFormat.commonFormat,
                interleaved: inputFormat.isInterleaved
            )
        } catch {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw WhisperVoiceStartFailure(
                stage: .nativeFileOpenFailed,
                underlying: error,
                context: Self.sessionContext(session).merging([
                    "file_name": nativeURL.lastPathComponent,
                    "actual_sample_rate": String(Int(inputFormat.sampleRate.rounded())),
                    "actual_input_channels": String(inputFormat.channelCount)
                ]) { _, new in new }
            )
        }

        let sink = NativeAudioSink(file: nativeFile, sampleRate: inputFormat.sampleRate)
        destination = url
        nativeDestination = nativeURL
        audioEngine = engine
        audioSink = sink
        LocalVoiceDiagnosticReport.shared.record(
            "RECORDER_INIT",
            "component=AVAudioEngine status=success file_name=\(nativeURL.lastPathComponent)"
        )
        LocalVoiceDiagnosticReport.shared.record(
            "FILE_CREATED",
            "file_created=\(FileManager.default.fileExists(atPath: nativeURL.path)) file_name=\(nativeURL.lastPathComponent)"
        )

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: nil) { buffer, _ in
            sink.append(buffer)
        }
        tapInstalled = true
        engine.prepare()
        LocalVoiceDiagnosticReport.shared.record(
            "PREPARE",
            "component=AVAudioEngine status=success"
        )
        do {
            try engine.start()
        } catch {
            cancel()
            throw WhisperVoiceStartFailure(
                stage: .audioEngineStartFailed,
                underlying: error,
                context: Self.sessionContext(session).merging([
                    "actual_sample_rate": String(Int(inputFormat.sampleRate.rounded())),
                    "actual_input_channels": String(inputFormat.channelCount)
                ]) { _, new in new }
            )
        }
        guard engine.isRunning else {
            cancel()
            throw WhisperVoiceStartFailure(
                stage: .recordFailed,
                context: Self.sessionContext(session)
            )
        }
        LocalVoiceDiagnosticReport.shared.record(
            "RECORD",
            "component=AVAudioEngine status=success running=true"
        )
        LocalVoiceDiagnosticReport.shared.record(
            "IS_RECORDING",
            "is_recording=true running=true"
        )
        LocalVoiceDiagnosticReport.shared.record(
            "whisper_audio_recording_started",
            "sample_rate=\(Int(inputFormat.sampleRate.rounded())) channels=\(inputFormat.channelCount) input=native route=\(Self.routeName(session))"
        )
    }

    func updateMeters() {}

    func finish() -> WhisperRecordingArtifact? {
        guard let engine = audioEngine,
              let sink = audioSink,
              let destination,
              let nativeDestination else { return nil }
        engine.stop()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        sink.close()
        let duration = sink.duration
        let writeError = sink.error
        audioEngine = nil
        audioSink = nil
        self.destination = nil
        self.nativeDestination = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let nativeSize = (try? nativeDestination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        LocalVoiceDiagnosticReport.shared.record(
            "FILE_SIZE",
            "file_created=\(FileManager.default.fileExists(atPath: nativeDestination.path)) file_size=\(nativeSize) duration=\(Int((duration * 1_000).rounded()))"
        )
        if let writeError {
            let failure = WhisperVoiceStartFailure(stage: .audioFileWriteFailed, underlying: writeError)
            LocalVoiceDiagnosticReport.shared.record("whisper_audio_write_failed", failure.diagnosticDetails)
            try? FileManager.default.removeItem(at: nativeDestination)
            try? FileManager.default.removeItem(at: destination)
            return nil
        }
        guard duration > 0, nativeSize > 0 else {
            try? FileManager.default.removeItem(at: nativeDestination)
            try? FileManager.default.removeItem(at: destination)
            return nil
        }
        LocalVoiceDiagnosticReport.shared.record("CONVERSION_PRE", "status=begin")
        do {
            try WhisperWaveConverter.convert(
                nativeAudioAt: nativeDestination,
                toWhisperWaveAt: destination
            )
        } catch {
            let failure = error as NSError
            LocalVoiceDiagnosticReport.shared.record(
                "whisper_audio_conversion_failed",
                "stage=AUDIO_CONVERSION_FAILED error_domain=\(failure.domain) error_code=\(failure.code) status=error"
            )
            try? FileManager.default.removeItem(at: nativeDestination)
            try? FileManager.default.removeItem(at: destination)
            return nil
        }
        LocalVoiceDiagnosticReport.shared.record("CONVERSION_POST", "status=success")
        try? FileManager.default.removeItem(at: nativeDestination)
        let outputSize = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard outputSize > 44 else {
            try? FileManager.default.removeItem(at: destination)
            return nil
        }
        LocalVoiceDiagnosticReport.shared.record(
            "WHISPER_INPUT_READY",
            "file_created=true file_size=\(outputSize) sample_rate=16000 channels=1"
        )
        return .init(url: destination, duration: duration)
    }

    func cancel() {
        audioEngine?.stop()
        if tapInstalled {
            audioEngine?.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        audioSink?.close()
        audioEngine = nil
        audioSink = nil
        if let destination { try? FileManager.default.removeItem(at: destination) }
        if let nativeDestination { try? FileManager.default.removeItem(at: nativeDestination) }
        destination = nil
        nativeDestination = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func routeName(_ session: AVAudioSession) -> String {
        session.currentRoute.inputs.first?.portType.rawValue ?? "none"
    }

    private static func sessionContext(_ session: AVAudioSession) -> [String: String] {
        [
            "category": session.category.rawValue,
            "mode": session.mode.rawValue,
            "actual_sample_rate": String(Int(session.sampleRate.rounded())),
            "actual_input_channels": String(session.inputNumberOfChannels),
            "input_available": String(session.isInputAvailable),
            "route": routeName(session)
        ]
    }

    private static func sessionDetails(_ session: AVAudioSession, status: String) -> String {
        sessionContext(session).merging(["status": status]) { _, new in new }
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
    }
}

enum WhisperWaveConverter {
    private final class InputProvider: @unchecked Sendable {
        private let lock = NSLock()
        private let file: AVAudioFile
        private let format: AVAudioFormat
        private var reachedEnd = false
        private var storedError: Error?

        init(file: AVAudioFile, format: AVAudioFormat) {
            self.file = file
            self.format = format
        }

        var error: Error? { lock.withLock { storedError } }
        var isAtEnd: Bool { lock.withLock { reachedEnd } }

        func next(
            requestedPackets: AVAudioPacketCount,
            status: UnsafeMutablePointer<AVAudioConverterInputStatus>
        ) -> AVAudioBuffer? {
            lock.withLock {
                if reachedEnd {
                    status.pointee = .endOfStream
                    return nil
                }
                let remainingFrames = file.length - file.framePosition
                guard remainingFrames > 0 else {
                    reachedEnd = true
                    status.pointee = .endOfStream
                    return nil
                }
                let capacity = AVAudioFrameCount(min(
                    AVAudioFramePosition(max(1, requestedPackets)),
                    remainingFrames
                ))
                guard let inputBuffer = AVAudioPCMBuffer(
                    pcmFormat: format,
                    frameCapacity: capacity
                ) else {
                    status.pointee = .noDataNow
                    storedError = WhisperOfflineVoiceError.invalidWaveFormat
                    return nil
                }
                do {
                    try file.read(into: inputBuffer)
                } catch {
                    status.pointee = .noDataNow
                    storedError = error
                    return nil
                }
                guard inputBuffer.frameLength > 0 else {
                    reachedEnd = true
                    status.pointee = .endOfStream
                    return nil
                }
                status.pointee = .haveData
                return inputBuffer
            }
        }
    }

    static func convert(nativeAudioAt sourceURL: URL, toWhisperWaveAt destinationURL: URL) throws {
        let sourceFile: AVAudioFile
        do {
            sourceFile = try AVAudioFile(forReading: sourceURL)
        } catch {
            throw stageError(1, underlying: error)
        }
        let sourceFormat = sourceFile.processingFormat
        guard sourceFile.length > 0,
              sourceFormat.sampleRate > 0,
              sourceFormat.channelCount > 0,
              let outputFormat = AVAudioFormat(
                  commonFormat: .pcmFormatInt16,
                  sampleRate: WhisperOfflineVoiceConfiguration.sampleRate,
                  channels: WhisperOfflineVoiceConfiguration.channelCount,
                  interleaved: true
              ),
              let converter = AVAudioConverter(from: sourceFormat, to: outputFormat) else {
            throw WhisperOfflineVoiceError.invalidWaveFormat
        }
        try? FileManager.default.removeItem(at: destinationURL)
        let outputFile: AVAudioFile
        do {
            outputFile = try AVAudioFile(
                forWriting: destinationURL,
                settings: [
                    AVFormatIDKey: Int(kAudioFormatLinearPCM),
                    AVSampleRateKey: WhisperOfflineVoiceConfiguration.sampleRate,
                    AVNumberOfChannelsKey: Int(WhisperOfflineVoiceConfiguration.channelCount),
                    AVLinearPCMBitDepthKey: WhisperOfflineVoiceConfiguration.bitDepth,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ],
                commonFormat: .pcmFormatInt16,
                interleaved: true
            )
        } catch {
            throw stageError(2, underlying: error)
        }
        let outputCapacity: AVAudioFrameCount = 4_096
        let inputProvider = InputProvider(file: sourceFile, format: sourceFormat)

        while true {
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: outputCapacity
            ) else { throw WhisperOfflineVoiceError.invalidWaveFormat }
            var conversionError: NSError?
            let status = converter.convert(to: outputBuffer, error: &conversionError) { requestedPackets, inputStatus in
                inputProvider.next(requestedPackets: requestedPackets, status: inputStatus)
            }
            if let readError = inputProvider.error { throw stageError(3, underlying: readError) }
            if let conversionError { throw stageError(4, underlying: conversionError) }
            if outputBuffer.frameLength > 0 {
                do { try outputFile.write(from: outputBuffer) }
                catch { throw stageError(5, underlying: error) }
            }
            switch status {
            case .haveData:
                continue
            case .endOfStream:
                return
            case .inputRanDry:
                if inputProvider.isAtEnd { return }
            case .error:
                throw WhisperOfflineVoiceError.invalidWaveFormat
            @unknown default:
                throw WhisperOfflineVoiceError.invalidWaveFormat
            }
        }
    }

    private static func stageError(_ stage: Int, underlying: Error) -> NSError {
        let value = underlying as NSError
        return NSError(
            domain: "WhisperWaveConverter",
            code: stage,
            userInfo: [
                NSUnderlyingErrorKey: value,
                NSLocalizedDescriptionKey: "stage=\(stage) underlying_domain=\(value.domain) underlying_code=\(value.code)"
            ]
        )
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
    private(set) var lifecyclePhase: WhisperVoiceLifecyclePhase = .idle

    private let recorder: any WhisperAudioRecording
    private let transcriber: any WhisperOfflineTranscribing
    private let microphoneAuthorization: @Sendable () async -> WhisperMicrophonePermissionState
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
        microphoneAuthorization: (@Sendable () async -> WhisperMicrophonePermissionState)? = nil,
        contextualVocabulary: @escaping @Sendable () async -> [String] = { [] },
        modelAvailable: @escaping @Sendable () -> Bool = { WhisperOfflineVoiceConfiguration.modelURL() != nil },
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.recorder = recorder ?? AppleWhisperAudioRecorder()
        self.transcriber = transcriber ?? WhisperTranscriptionEngine()
        if let microphoneAuthorization {
            self.microphoneAuthorization = microphoneAuthorization
        } else if let authorization {
            self.microphoneAuthorization = {
                await authorization() ? .authorized : .denied
            }
        } else {
            self.microphoneAuthorization = Self.resolveMicrophoneAuthorization
        }
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
        LocalVoiceDiagnosticReport.shared.record("VOICE_TAP", "source=home status=received")
        LocalVoiceDiagnosticReport.shared.record(
            "start_listening_invoked",
            "provider=whisper mechanism=offline"
        )
        setLifecyclePhase(.requestingPermission)
        setState(.requestingPermission)
        let permission = await microphoneAuthorization()
        LocalVoiceDiagnosticReport.shared.record(
            "MIC_PERMISSION",
            "permission_state=\(permission.rawValue) granted=\(permission == .authorized)"
        )
        guard permission == .authorized else {
            guard activeSessionID == sessionID else { return }
            activeSessionID = nil
            let failure = WhisperVoiceStartFailure(
                stage: .micPermissionDenied,
                context: ["permission_state": permission.rawValue]
            )
            LocalVoiceDiagnosticReport.shared.record("whisper_recording_failed", failure.diagnosticDetails)
            setState(.denied)
            setLifecyclePhase(.idle)
            finishFailedDiagnosticRequest(details: failure.diagnosticDetails)
            return
        }
        guard activeSessionID == sessionID else { return }
        guard modelAvailable() else {
            activeSessionID = nil
            let details = "stage=WHISPER_MODEL_LOOKUP internal_code=MODEL_MISSING status=error"
            LocalVoiceDiagnosticReport.shared.record("whisper_model_missing", details)
            setState(.unavailable)
            setLifecyclePhase(.idle)
            finishFailedDiagnosticRequest(details: details)
            return
        }
        let destination = temporaryDirectory.appendingPathComponent("ua-whisper-\(sessionID.uuidString).wav")
        setLifecyclePhase(.preparing)
        do {
            try recorder.start(at: destination)
            guard activeSessionID == sessionID else {
                recorder.cancel()
                return
            }
            setLifecyclePhase(.recording)
            setState(.listening)
            startEndpointMonitoring(sessionID: sessionID)
        } catch {
            guard activeSessionID == sessionID else { return }
            activeSessionID = nil
            recorder.cancel()
            let failure = error as? WhisperVoiceStartFailure
                ?? WhisperVoiceStartFailure(stage: .recorderInitFailed, underlying: error)
            LocalVoiceDiagnosticReport.shared.record(
                "whisper_recording_failed",
                failure.diagnosticDetails
            )
            setState(.failed)
            setLifecyclePhase(.idle)
            finishFailedDiagnosticRequest(details: failure.diagnosticDetails)
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
        setLifecyclePhase(.stopping)
        LocalVoiceDiagnosticReport.shared.record("STOPPING", "reason=\(reason.rawValue) status=begin")
        setLifecyclePhase(.converting)
        guard let artifact = recorder.finish() else {
            let details = "stage=AUDIO_FINISH internal_code=EMPTY_OR_INVALID_AUDIO status=error"
            LocalVoiceDiagnosticReport.shared.record("whisper_audio_empty", details)
            setState(.failed)
            setLifecyclePhase(.idle)
            finishFailedDiagnosticRequest(details: details)
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
        setLifecyclePhase(.transcribing)
        LocalVoiceDiagnosticReport.shared.record("WHISPER_START", "language=uk status=begin")
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
                LocalVoiceDiagnosticReport.shared.record("WHISPER_RESULT", "status=success length=\(finalTranscript.count)")
                self.transcriptionID = nil
                self.cancellation = nil
                self.transcriptionTask = nil
                self.setLifecyclePhase(.result)
                self.setState(.idle)
                self.setLifecyclePhase(.idle)
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
                self.setLifecyclePhase(.idle)
                self.finishFailedDiagnosticRequest(
                    details: "stage=WHISPER_TRANSCRIPTION internal_code=TRANSCRIPTION_FAILED error_type=\(String(describing: type(of: error))) status=error"
                )
            }
        }
    }

    private func cancelCurrentSession(reason: VoiceStopReason, publishIdle: Bool = true) {
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
        setLifecyclePhase(.idle)
        if publishIdle && (state == .listening || state == .requestingPermission || state == .transcribing) {
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

    func handleInterruption() {
        LocalVoiceDiagnosticReport.shared.record("audio_interruption", "state=began provider=whisper")
        cancelCurrentSession(reason: .audioInterruption, publishIdle: false)
        setState(.failed)
        finishFailedDiagnosticRequest(
            details: "stage=AUDIO_INTERRUPTION internal_code=AUDIO_INTERRUPTION status=error"
        )
    }

    private func handleRouteChange(_ evidence: AudioRouteChangeEvidence) {
        LocalVoiceDiagnosticReport.shared.record("route_change", evidence.diagnosticDescription)
        if evidence.requiresVoiceCaptureStop {
            cancelCurrentSession(reason: .routeChange, publishIdle: false)
            setState(.failed)
            finishFailedDiagnosticRequest(
                details: "stage=AUDIO_ROUTE_CHANGE internal_code=AUDIO_ROUTE_CONFLICT reason=\(evidence.reasonName) status=error"
            )
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

    private func setLifecyclePhase(_ newPhase: WhisperVoiceLifecyclePhase) {
        lifecyclePhase = newPhase
        LocalVoiceDiagnosticReport.shared.record("voice_lifecycle", "state=\(newPhase.rawValue)")
    }

    private func finishFailedDiagnosticRequest(details: String) {
        LocalVoiceDiagnosticReport.shared.recordTerminal(.error, details: details)
        guard let session = LocalVoiceDiagnosticReport.shared.completedSession() else { return }
        Task { await PhysicalDiagnosticDelivery.shared.enqueue(session) }
    }

    private nonisolated static func resolveMicrophoneAuthorization() async -> WhisperMicrophonePermissionState {
        let before = AVAudioApplication.shared.recordPermission
        LocalVoiceDiagnosticReport.shared.record(
            "microphone_permission_before",
            "permission_state=\(permissionState(before).rawValue)"
        )
        switch before {
        case .granted:
            return .authorized
        case .denied:
            return .denied
        case .undetermined:
            let granted = await AVAudioApplication.requestRecordPermission()
            let after = AVAudioApplication.shared.recordPermission
            let state = granted && after == .granted ? WhisperMicrophonePermissionState.authorized : permissionState(after)
            LocalVoiceDiagnosticReport.shared.record(
                "microphone_permission_after",
                "permission_state=\(state.rawValue) granted=\(granted)"
            )
            return state
        @unknown default:
            return .restricted
        }
    }

    private nonisolated static func permissionState(
        _ permission: AVAudioApplication.recordPermission
    ) -> WhisperMicrophonePermissionState {
        switch permission {
        case .granted: .authorized
        case .denied: .denied
        case .undetermined: .undetermined
        @unknown default: .restricted
        }
    }
}
