import AVFoundation
import CryptoKit
import Foundation
import Testing
@testable import UniversalAssistant

@MainActor
private final class StubWhisperRecorder: WhisperAudioRecording {
    var isRecording = false
    var currentTime: TimeInterval = 1.25
    var averagePower: Float = -20
    var returnsArtifact = true
    var startError: Error?
    private(set) var startCount = 0
    private(set) var cancelCount = 0
    private var url: URL?

    func start(at url: URL) throws {
        startCount += 1
        if let startError { throw startError }
        self.url = url
        isRecording = true
        try Data(repeating: 0, count: 64).write(to: url, options: .atomic)
    }

    func updateMeters() {}

    func finish() -> WhisperRecordingArtifact? {
        isRecording = false
        guard returnsArtifact, let url else { return nil }
        self.url = nil
        return .init(url: url, duration: currentTime)
    }

    func cancel() {
        cancelCount += 1
        isRecording = false
        if let url { try? FileManager.default.removeItem(at: url) }
        url = nil
    }
}

private actor StubWhisperTranscriber: WhisperOfflineTranscribing {
    private var outputs: [String]
    private let delay: Duration
    private(set) var calls = 0
    private(set) var receivedPrompts: [[String]] = []

    init(outputs: [String], delay: Duration = .zero) {
        self.outputs = outputs
        self.delay = delay
    }

    func transcribe(
        audioURL _: URL,
        promptEntries: [String],
        cancellation: WhisperCancellationToken
    ) async throws -> String {
        calls += 1
        receivedPrompts.append(promptEntries)
        let output = outputs.isEmpty ? "" : outputs.removeFirst()
        if delay > .zero { try? await Task.sleep(for: delay) }
        guard !cancellation.isCancelled else { throw WhisperOfflineVoiceError.cancelled }
        return output
    }

    func releaseModel() async {}
}

private final class CapturingEvidenceParser: EvidenceAwareCommandParsing, @unchecked Sendable {
    private let lock = NSLock()
    private var capturedText = ""
    private var capturedEvidence: VoiceRecognitionEvidence?

    func parse(_ text: String) -> StructuredCommand {
        parse(text, speechEvidence: nil)
    }

    func parse(_ text: String, speechEvidence: VoiceRecognitionEvidence?) -> StructuredCommand {
        lock.withLock {
            capturedText = text
            capturedEvidence = speechEvidence
        }
        return StructuredCommand(
            originalText: text,
            normalizedText: text.lowercased(),
            language: .uk,
            intent: .unknown
        )
    }

    var snapshot: (text: String, hasEvidence: Bool) {
        lock.withLock { (capturedText, capturedEvidence != nil) }
    }
}

@Suite("Offline whisper.cpp voice input", .serialized)
@MainActor
struct WhisperOfflineVoiceInputTests {
    @Test func exactModelNameIsSmallQ51() {
        #expect(WhisperOfflineVoiceConfiguration.modelName == "ggml-small-q5_1")
        #expect(WhisperOfflineVoiceConfiguration.modelExtension == "bin")
    }

    @Test func bundledModelExistsWithExpectedIntegrity() throws {
        let url = try #require(WhisperOfflineVoiceConfiguration.modelURL())
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        #expect(Int64(values.fileSize ?? 0) == WhisperOfflineVoiceConfiguration.expectedModelByteCount)
        let digest = SHA256.hash(data: try Data(contentsOf: url, options: .mappedIfSafe))
            .map { String(format: "%02x", $0) }.joined()
        #expect(digest == WhisperOfflineVoiceConfiguration.expectedModelSHA256)
    }

    @Test func bundledModelLoadsIntoOfficialWhisperContext() async throws {
        let url = try #require(WhisperOfflineVoiceConfiguration.modelURL())
        let engine = WhisperTranscriptionEngine(modelURL: url)
        try await engine.validateModelLoad()
        await engine.releaseModel()
    }

    @Test func corruptModelFailsWithoutCrashingTheApplication() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper-corrupt-model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("ggml-small-q5_1.bin")
        try Data("not-a-whisper-model".utf8).write(to: url, options: .atomic)
        let engine = WhisperTranscriptionEngine(modelURL: url)
        await #expect(throws: WhisperOfflineVoiceError.modelLoadFailed) {
            try await engine.validateModelLoad()
        }
    }

    @Test func runtimeLoadsWhisperFromEmbeddedAppFrameworksDirectory() throws {
        let frameworksDirectory = try #require(Bundle.main.privateFrameworksURL)
        let whisperBinary = frameworksDirectory
            .appendingPathComponent("whisper.framework", isDirectory: true)
            .appendingPathComponent("whisper")
        #expect(FileManager.default.fileExists(atPath: whisperBinary.path))
    }

    @Test func architectureHasNoNetworkDependency() {
        #expect(!WhisperOfflineVoiceConfiguration.requiresNetwork)
    }

    @Test func whisperWaveSettingsArePCM16At16kMono() {
        let settings = AppleWhisperAudioRecorder.recordingSettings
        #expect(settings[AVFormatIDKey] as? Int == Int(kAudioFormatLinearPCM))
        #expect(settings[AVSampleRateKey] as? Double == 16_000)
        #expect(settings[AVNumberOfChannelsKey] as? Int == 1)
        #expect(settings[AVLinearPCMBitDepthKey] as? Int == 16)
        #expect(settings[AVLinearPCMIsFloatKey] as? Bool == false)
        #expect(settings[AVLinearPCMIsBigEndianKey] as? Bool == false)
    }

    @Test func nativeCaptureUsesNegotiatedHardwareSampleRate() {
        let settings = AppleWhisperAudioRecorder.nativeCaptureSettings(sampleRate: 48_000)
        #expect(settings[AVFormatIDKey] as? Int == Int(kAudioFormatLinearPCM))
        #expect(settings[AVSampleRateKey] as? Double == 48_000)
        #expect(settings[AVNumberOfChannelsKey] as? Int == 1)
        #expect(settings[AVLinearPCMBitDepthKey] as? Int == 16)
    }

    @Test func nativeAudioIsConvertedToWhisperWave() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper-conversion-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("native.caf")
        let outputURL = directory.appendingPathComponent("whisper.wav")
        let inputFormat = try #require(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ))
        let frameCount: AVAudioFrameCount = 48_000
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount))
        buffer.frameLength = frameCount
        let samples = try #require(buffer.floatChannelData?.pointee)
        for index in 0..<Int(frameCount) {
            samples[index] = 0.1 * sin(2 * .pi * 440 * Float(index) / 48_000)
        }
        do {
            try autoreleasepool {
                let sourceFile = try AVAudioFile(forWriting: sourceURL, settings: inputFormat.settings)
                try sourceFile.write(from: buffer)
            }
        } catch {
            Issue.record("Не вдалося створити native fixture: \(error)")
            return
        }

        do {
            try WhisperWaveConverter.convert(nativeAudioAt: sourceURL, toWhisperWaveAt: outputURL)
        } catch {
            let value = error as NSError
            Issue.record("Не вдалася native→Whisper конвертація: domain=\(value.domain) code=\(value.code) description=\(value.localizedDescription)")
            return
        }

        let outputFile = try AVAudioFile(forReading: outputURL)
        #expect(abs(outputFile.fileFormat.sampleRate - 16_000) < 0.5)
        #expect(outputFile.fileFormat.channelCount == 1)
        #expect(outputFile.length > 15_000)
        #expect(try WhisperWaveFile.samples(from: outputURL).count > 15_000)
    }

    @Test func productionNativeAudioEngineStartsAndProducesWhisperInput() async throws {
        guard ProcessInfo.processInfo.environment["UA_LIVE_AUDIO_CAPTURE"] == "1" else { return }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper-live-capture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = AppleWhisperAudioRecorder()
        let destination = directory.appendingPathComponent("capture.wav")
        try recorder.start(at: destination)
        #expect(recorder.isRecording)
        try await Task.sleep(for: .seconds(1))
        let artifact = try #require(recorder.finish())
        #expect(artifact.duration > 0)
        #expect(FileManager.default.fileExists(atPath: artifact.url.path))
        #expect((try artifact.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 44)
        let file = try AVAudioFile(forReading: artifact.url)
        #expect(abs(file.fileFormat.sampleRate - 16_000) < 0.5)
        #expect(file.fileFormat.channelCount == 1)
    }

    @Test func audioTapCallbackIsSendableNonisolatedAndCopiesOnBackgroundExecutor() async throws {
        let sink = WhisperNativeAudioSink(sampleRate: 48_000, maximumDuration: 1)
        let callback = WhisperAudioTapTrampoline.make(sink: sink)
        let result = await Task.detached { () -> (Int, TimeInterval, Float) in
            guard let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48_000,
                channels: 1,
                interleaved: false
            ),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024),
            let samples = buffer.floatChannelData?.pointee else { return (0, 0, -160) }
            buffer.frameLength = 1_024
            for index in 0..<1_024 { samples[index] = 0.1 }
            callback(buffer, AVAudioTime(sampleTime: 0, atRate: 48_000))
            return (sink.receivedBufferCount, sink.duration, sink.averagePower)
        }.value
        #expect(result.0 == 1)
        #expect(result.1 > 0)
        #expect(result.2 > -30)
        #expect(sink.stopAcceptingAndWaitForCallback())
        let nativeBuffer = try #require(sink.makeNativeBuffer())
        #expect(nativeBuffer.frameLength == 1_024)
    }

    @Test func twentyBackgroundAudioTapCyclesRemainBoundedAndRaceFree() async {
        for _ in 0..<20 {
            let sink = WhisperNativeAudioSink(sampleRate: 48_000, maximumDuration: 1)
            let callback = WhisperAudioTapTrampoline.make(sink: sink)
            let count = await Task.detached { () -> Int in
                guard let format = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: 48_000,
                    channels: 1,
                    interleaved: false
                ),
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512),
                let samples = buffer.floatChannelData?.pointee else { return 0 }
                buffer.frameLength = 512
                for index in 0..<512 { samples[index] = Float(index % 8) / 16 }
                callback(buffer, AVAudioTime(sampleTime: 0, atRate: 48_000))
                return sink.receivedBufferCount
            }.value
            #expect(count == 1)
            #expect(sink.stopAcceptingAndWaitForCallback())
            #expect(sink.makeNativeBuffer()?.frameLength == 512)
        }
    }

    @Test func languageIsUkrainian() {
        #expect(WhisperOfflineVoiceConfiguration.language == "uk")
    }

    @Test func taskIsTranscribeNotTranslate() {
        #expect(WhisperOfflineVoiceConfiguration.task == "transcribe")
    }

    @Test func fullTranscriptIsDeliveredAsOneFinalEvent() async {
        let recorder = StubWhisperRecorder()
        let transcriber = StubWhisperTranscriber(outputs: ["Знайди чоловічі кросівки Adidas сорок другого розміру"])
        let controller = makeController(recorder: recorder, transcriber: transcriber)
        var transcripts: [(String, Bool)] = []
        controller.setEventHandler {
            if case let .transcript(text, isFinal) = $0 { transcripts.append((text, isFinal)) }
        }
        await controller.start(locale: Locale(identifier: "uk-UA"))
        controller.stop(reason: .userPressedStop)
        await waitUntil { controller.state == .idle }
        #expect(transcripts.count == 1)
        #expect(transcripts.first?.0 == "Знайди чоловічі кросівки Adidas сорок другого розміру")
        #expect(transcripts.first?.1 == true)
    }

    @Test func existingEditableComposerReceivesTranscript() async {
        let recorder = StubWhisperRecorder()
        let transcriber = StubWhisperTranscriber(outputs: ["Покажи погоду завтра"])
        let controller = makeController(recorder: recorder, transcriber: transcriber)
        let model = AssistantViewModel(voiceInput: controller)
        await controller.start(locale: Locale(identifier: "uk-UA"))
        controller.stop(reason: .userPressedStop)
        await waitUntil { controller.state == .idle }
        #expect(model.input == "Покажи погоду завтра")
    }

    @Test func manualEditRemainsAuthoritative() async {
        let recorder = StubWhisperRecorder()
        let transcriber = StubWhisperTranscriber(outputs: ["Покажи погоду завтра"])
        let controller = makeController(recorder: recorder, transcriber: transcriber)
        let parser = CapturingEvidenceParser()
        let model = AssistantViewModel(commandEngine: parser, voiceInput: controller)
        await controller.start(locale: Locale(identifier: "uk-UA"))
        controller.stop(reason: .userPressedStop)
        await waitUntil { controller.state == .idle }
        model.input = "Покажи погоду післязавтра"
        model.submit()
        #expect(parser.snapshot.text == "Покажи погоду післязавтра")
        #expect(!parser.snapshot.hasEvidence)
    }

    @Test func uneditedVoiceDraftRetainsRecognitionEvidenceOnSubmit() async {
        let recorder = StubWhisperRecorder()
        let transcriber = StubWhisperTranscriber(outputs: ["Покажи погоду завтра"])
        let controller = makeController(recorder: recorder, transcriber: transcriber)
        let parser = CapturingEvidenceParser()
        let model = AssistantViewModel(commandEngine: parser, voiceInput: controller)
        await controller.start(locale: Locale(identifier: "uk-UA"))
        controller.stop(reason: .userPressedStop)
        await waitUntil { controller.state == .idle }
        model.submit()
        #expect(parser.snapshot.text == "Покажи погоду завтра")
        #expect(parser.snapshot.hasEvidence)
    }

    @Test func finalTranscriptDoesNotAutoExecute() async {
        let recorder = StubWhisperRecorder()
        let transcriber = StubWhisperTranscriber(outputs: ["Постав таймер на хвилину"])
        let controller = makeController(recorder: recorder, transcriber: transcriber)
        let model = AssistantViewModel(voiceInput: controller)
        await controller.start(locale: Locale(identifier: "uk-UA"))
        controller.stop(reason: .userPressedStop)
        await waitUntil { controller.state == .idle }
        #expect(model.resultState == .idle)
        #expect(model.input == "Постав таймер на хвилину")
        #expect(!WhisperOfflineVoiceConfiguration.automaticallySubmits)
    }

    @Test func productionCompositionSelectsWhisperNotAppleSpeech() {
        let model = ProductionAssistantComposition.makeModel(personalSearchSources: [])
        #expect(model.voiceInputEngineIdentifier == "whisper.cpp")
        #expect(!WhisperOfflineVoiceConfiguration.usesAppleSpeech)
    }

    @Test func secondStartCancelsFirstRecorderBeforeRestart() async {
        let recorder = StubWhisperRecorder()
        let transcriber = StubWhisperTranscriber(outputs: ["Друга команда"])
        let controller = makeController(recorder: recorder, transcriber: transcriber)
        await controller.start(locale: Locale(identifier: "uk-UA"))
        await controller.start(locale: Locale(identifier: "uk-UA"))
        #expect(recorder.startCount == 2)
        #expect(recorder.cancelCount >= 2)
        controller.stop(reason: .externalRequest)
    }

    @Test func authorizedPermissionTransitionsDeterministicallyToRecording() async {
        let recorder = StubWhisperRecorder()
        let controller = WhisperVoiceInputController(
            recorder: recorder,
            transcriber: StubWhisperTranscriber(outputs: []),
            microphoneAuthorization: { .authorized },
            modelAvailable: { true }
        )
        await controller.start(locale: Locale(identifier: "uk-UA"))
        #expect(controller.state == .listening)
        #expect(controller.lifecyclePhase == .recording)
        #expect(recorder.startCount == 1)
        controller.stop(reason: .externalRequest)
        #expect(controller.lifecyclePhase == .idle)
    }

    @Test func restrictedPermissionNeverTouchesTheAudioOwner() async {
        let recorder = StubWhisperRecorder()
        let controller = WhisperVoiceInputController(
            recorder: recorder,
            transcriber: StubWhisperTranscriber(outputs: []),
            microphoneAuthorization: { .restricted },
            modelAvailable: { true }
        )
        await controller.start(locale: Locale(identifier: "uk-UA"))
        #expect(controller.state == .denied)
        #expect(controller.lifecyclePhase == .idle)
        #expect(recorder.startCount == 0)
    }

    @Test func missingNSErrorDoesNotInventAnOSStatus() {
        let failure = WhisperVoiceStartFailure(stage: .recordFailed)
        #expect(failure.errorDomain == "none")
        #expect(failure.errorCode == 0)
        #expect(!failure.diagnosticDetails.contains("osstatus="))
    }

    @Test func realOSStatusIsPreservedExactly() {
        let error = NSError(domain: NSOSStatusErrorDomain, code: -50)
        let failure = WhisperVoiceStartFailure(stage: .audioEngineStartFailed, underlying: error)
        #expect(failure.diagnosticDetails.contains("error_domain=NSOSStatusErrorDomain"))
        #expect(failure.diagnosticDetails.contains("error_code=-50"))
        #expect(failure.diagnosticDetails.contains("osstatus=-50"))
    }

    @Test func voiceStartFailurePreservesExactStage() async {
        let recorder = StubWhisperRecorder()
        recorder.startError = WhisperVoiceStartFailure(stage: .recordFailed)
        let controller = makeController(
            recorder: recorder,
            transcriber: StubWhisperTranscriber(outputs: [])
        )
        await controller.start(locale: Locale(identifier: "uk-UA"))
        #expect(controller.state == .failed)
        #expect(recorder.startCount == 1)
        #expect(recorder.cancelCount >= 2)
    }

    @Test func repeatedRecordingCyclesRemainSerialized() async {
        let recorder = StubWhisperRecorder()
        let outputs = (0..<20).map { "Команда \($0)" }
        let transcriber = StubWhisperTranscriber(outputs: outputs)
        let controller = makeController(recorder: recorder, transcriber: transcriber)
        for _ in 0..<20 {
            await controller.start(locale: Locale(identifier: "uk-UA"))
            #expect(controller.state == .listening)
            controller.stop(reason: .userPressedStop)
            await waitUntil { controller.state == .idle }
        }
        #expect(recorder.startCount == 20)
        #expect(await transcriber.calls == 20)
    }

    @Test func fastRepeatedStartsKeepExactlyOneCurrentRecorderOwner() async {
        let recorder = StubWhisperRecorder()
        let controller = makeController(
            recorder: recorder,
            transcriber: StubWhisperTranscriber(outputs: [])
        )
        for _ in 0..<20 {
            await controller.start(locale: Locale(identifier: "uk-UA"))
        }
        #expect(recorder.startCount == 20)
        #expect(recorder.cancelCount >= 20)
        #expect(controller.state == .listening)
        #expect(controller.lifecyclePhase == .recording)
        controller.stop(reason: .externalRequest)
        #expect(!recorder.isRecording)
        #expect(controller.lifecyclePhase == .idle)
    }

    @Test func interruptionAllowsCleanSecondRecording() async {
        let recorder = StubWhisperRecorder()
        let controller = makeController(
            recorder: recorder,
            transcriber: StubWhisperTranscriber(outputs: ["Після переривання"])
        )
        await controller.start(locale: Locale(identifier: "uk-UA"))
        controller.handleInterruption()
        #expect(controller.state == .failed)
        #expect(!recorder.isRecording)
        await controller.start(locale: Locale(identifier: "uk-UA"))
        #expect(controller.state == .listening)
        controller.stop(reason: .userPressedStop)
        await waitUntil { controller.state == .idle }
        #expect(controller.transcript == "Після переривання")
    }

    @Test func cancelledGenerationCannotPublishStaleTranscript() async {
        let recorder = StubWhisperRecorder()
        let transcriber = StubWhisperTranscriber(
            outputs: ["Стара команда", "Нова команда"],
            delay: .milliseconds(100)
        )
        let controller = makeController(recorder: recorder, transcriber: transcriber)
        var finals: [String] = []
        controller.setEventHandler {
            if case let .transcript(text, true) = $0 { finals.append(text) }
        }
        await controller.start(locale: Locale(identifier: "uk-UA"))
        controller.stop(reason: .userPressedStop)
        await controller.start(locale: Locale(identifier: "uk-UA"))
        controller.stop(reason: .userPressedStop)
        await waitUntil { controller.state == .idle }
        #expect(finals == ["Нова команда"])
    }

    @Test func emptyRecordingProducesTruthfulFailure() async {
        let recorder = StubWhisperRecorder()
        recorder.returnsArtifact = false
        let controller = makeController(
            recorder: recorder,
            transcriber: StubWhisperTranscriber(outputs: [])
        )
        await controller.start(locale: Locale(identifier: "uk-UA"))
        controller.stop(reason: .userPressedStop)
        #expect(controller.state == .failed)
        #expect(controller.transcript.isEmpty)
    }

    @Test func deniedMicrophonePermissionNeverStartsRecorder() async {
        let recorder = StubWhisperRecorder()
        let controller = WhisperVoiceInputController(
            recorder: recorder,
            transcriber: StubWhisperTranscriber(outputs: []),
            authorization: { false },
            modelAvailable: { true }
        )
        await controller.start(locale: Locale(identifier: "uk-UA"))
        #expect(controller.state == .denied)
        #expect(recorder.startCount == 0)
    }

    @Test func missingModelProducesTruthfulUnavailableState() async {
        let recorder = StubWhisperRecorder()
        let controller = WhisperVoiceInputController(
            recorder: recorder,
            transcriber: StubWhisperTranscriber(outputs: []),
            authorization: { true },
            modelAvailable: { false }
        )
        await controller.start(locale: Locale(identifier: "uk-UA"))
        #expect(controller.state == .unavailable)
        #expect(recorder.startCount == 0)
    }

    @Test func temporaryWaveIsRemovedAfterSuccessfulTranscription() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper-cleanup-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let recorder = StubWhisperRecorder()
        let controller = makeController(
            recorder: recorder,
            transcriber: StubWhisperTranscriber(outputs: ["Тест"]),
            temporaryDirectory: directory
        )
        await controller.start(locale: Locale(identifier: "uk-UA"))
        controller.stop(reason: .userPressedStop)
        await waitUntil { controller.state == .idle }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        #expect(files.isEmpty)
    }

    @Test func ordinaryUkrainianIsNotSemanticallyRewritten() async {
        let expected = "Постав таймер на сім хвилин тридцять секунд"
        let recorder = StubWhisperRecorder()
        let controller = makeController(
            recorder: recorder,
            transcriber: StubWhisperTranscriber(outputs: [expected])
        )
        await controller.start(locale: Locale(identifier: "uk-UA"))
        controller.stop(reason: .userPressedStop)
        await waitUntil { controller.state == .idle }
        #expect(controller.transcript == expected)
    }

    @Test func mixedLanguageProperNounsAreNotRewritten() async {
        let expected = "Порівняй Fujifilm X100VI та Xiaomi 15 Ultra"
        let recorder = StubWhisperRecorder()
        let controller = makeController(
            recorder: recorder,
            transcriber: StubWhisperTranscriber(outputs: [expected])
        )
        await controller.start(locale: Locale(identifier: "uk-UA"))
        controller.stop(reason: .userPressedStop)
        await waitUntil { controller.state == .idle }
        #expect(controller.transcript == expected)
    }

    @Test func dynamicPromptIsBoundedAndContainsNoFullCommands() {
        let entries = (0..<120).map { "Brand\($0)" } + ["Знайди повний тестовий запит для магазину"]
        let prompt = WhisperPromptBuilder.prompt(from: entries)
        #expect(prompt.split(separator: ",").count == WhisperOfflineVoiceConfiguration.maximumPromptEntries)
        #expect(!prompt.contains("Знайди повний тестовий запит"))
    }

    @Test func dynamicPromptDeduplicatesCanonicalNames() {
        let prompt = WhisperPromptBuilder.prompt(from: ["eBay", "ebay", "eBay", "AliExpress"])
        #expect(prompt == "eBay, AliExpress")
    }

    @Test func dynamicValuesCannotEvictCanonicalRegistryNames() {
        let dynamic = (0..<200).map { "Contact\($0)" }
        let canonical = VoiceRecognitionRequestConfiguration.canonicalWhisperVocabulary
        let prompt = WhisperPromptBuilder.prompt(dynamicEntries: dynamic, canonicalEntries: canonical)
        let entries = Set(prompt.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        })
        #expect(entries.count <= WhisperOfflineVoiceConfiguration.maximumPromptEntries)
        for provider in OfficialPublicProviderHandoffRegistry.records {
            #expect(entries.contains(provider.displayName))
        }
    }

    private func makeController(
        recorder: StubWhisperRecorder,
        transcriber: StubWhisperTranscriber,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) -> WhisperVoiceInputController {
        WhisperVoiceInputController(
            recorder: recorder,
            transcriber: transcriber,
            authorization: { true },
            contextualVocabulary: { ["Adidas", "Baldinini", "AliExpress"] },
            modelAvailable: { true },
            temporaryDirectory: temporaryDirectory
        )
    }

    private func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async {
        for _ in 0..<300 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Асинхронна операція Whisper не завершилася")
    }
}
