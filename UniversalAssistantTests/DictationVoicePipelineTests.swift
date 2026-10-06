import Foundation
import Speech
import Testing
@testable import UniversalAssistant

private actor DictationVocabularyGate {
    var continuation: CheckedContinuation<[String], Never>?
    func wait() async -> [String] { await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(returning: ["Моя користувацька фраза"]); continuation = nil }
    var waiting: Bool { continuation != nil }
}

private actor UnexpectedDictationCloud: CloudVoiceTranscribing {
    var calls = 0
    func transcribe(audioURL: URL, requestID: UUID, prompt: [String]) async throws -> String {
        calls += 1
        return "MUST NOT REPLACE APPLE"
    }
}

@MainActor
private final class ControlledDictationSession: DictationVoiceSession {
    var event: (@MainActor @Sendable (DictationVoiceEvent) -> Void)?
    var vocabulary: [String] = []
    var suspendStart = false
    var pending: CheckedContinuation<Void, Never>?
    var stops = 0
    func start(contextualStrings: [String], onEvent: @escaping @MainActor @Sendable (DictationVoiceEvent) -> Void) async throws {
        vocabulary = contextualStrings
        event = onEvent
        if suspendStart { await withCheckedContinuation { pending = $0 } }
    }
    func finish() async throws {}
    func stop() async { stops += 1 }
}

private final class DictationSubmittedTextParser: CommandParsing, @unchecked Sendable {
    private let lock = NSLock()
    private var captured: [String] = []
    var values: [String] { lock.withLock { captured } }
    func parse(_ text: String) -> StructuredCommand {
        lock.withLock { captured.append(text) }
        return .init(originalText: text, normalizedText: text.lowercased(), language: .uk, intent: .help)
    }
}

@MainActor
@Suite(.serialized)
struct DictationVoicePipelineTests {
    @Test func appleFinalFlowsThroughControllerAndViewModelOnceWithoutCloudOrVocabularyWait() async {
        let backend = ControlledDictationSession(), cloud = UnexpectedDictationCloud()
        let vocabulary = DictationVocabularyGate()
        let controller = VoiceInputController(
            authorization: { Issue.record("Legacy authorization must not delay Dictation"); return false },
            contextualVocabulary: { await vocabulary.wait() }, cloudTranscriber: cloud,
            dictationBackendFactory: { backend })
        let parser = DictationSubmittedTextParser()
        let model = AssistantViewModel(commandEngine: parser, voiceInput: controller)
        await controller.start()
        #expect(controller.state == .listening)
        let raw = "  Відкрий Telegram\n"
        backend.event?(.partial(raw))
        #expect(model.input == raw)
        backend.event?(.evidence(.init(primaryTranscript: raw, alternativeTranscripts: [],
                                      segmentAlternativeCount: 0, averageSegmentConfidence: nil)))
        backend.event?(.final(raw))
        backend.event?(.final("stale final must not execute"))
        #expect(parser.values == [raw])
        #expect(model.visibleVoiceTranscript == raw)
        #expect(await cloud.calls == 0)
        for _ in 0..<100 where !(await vocabulary.waiting) { await Task.yield() }
        await vocabulary.release()
    }

    @Test func closingWhileDictationStartIsSuspendedRejectsLateStartAndTranscript() async {
        let backend = ControlledDictationSession()
        backend.suspendStart = true
        let controller = VoiceInputController(dictationBackendFactory: { backend })
        var finals = 0
        controller.setEventHandler { if case .ios27AppleTranscript(_, true) = $0 { finals += 1 } }
        let start = Task { await controller.start() }
        for _ in 0..<100 where backend.pending == nil { await Task.yield() }
        #expect(backend.pending != nil)
        controller.stop(reason: .externalRequest)
        backend.event?(.final("Відкрий Viber"))
        backend.pending?.resume(); backend.pending = nil
        await start.value
        #expect(controller.state == .idle)
        #expect(finals == 0)
        #expect(backend.stops >= 1)
    }

    @Test func oldBackendCannotStopNewDictationGeneration() async {
        let old = ControlledDictationSession(), current = ControlledDictationSession()
        old.suspendStart = true
        var invocation = 0
        let controller = VoiceInputController(dictationBackendFactory: {
            invocation += 1; return invocation == 1 ? old : current
        })
        let first = Task { await controller.start() }
        for _ in 0..<100 where old.pending == nil { await Task.yield() }
        await controller.start()
        old.event?(.failure("stale"))
        old.event?(.final("stale"))
        old.pending?.resume(); old.pending = nil
        await first.value
        #expect(controller.state == .listening)
        #expect(current.stops == 0)
        current.event?(.final("Відкрий Telegram"))
        #expect(controller.transcript == "Відкрий Telegram")
        #expect(controller.state == .idle)
    }

    @Test func cachedUserContextDoesNotRemoveApplicationVocabulary() {
        let values = VoiceInputController.ios27ContextualVocabulary(additional:
            ["Моя фраза", "Моя фраза"] + (1...150).map { "Назва \($0)" })
        #expect(values.count <= 100)
        #expect(values.filter { $0 == "Моя фраза" }.count == 1)
        #expect(values.contains { $0.lowercased() == "telegram" })
        #expect(values.contains { $0.lowercased() == "viber" })
    }

    @Test func speechEvidenceContainsOnlyRealPublicAlternativesAndConfidence() {
        guard #available(iOS 26.0, *) else { return }
        var primary = AttributedString("Відкрий Telegram")
        primary[AttributeScopes.SpeechAttributes.ConfidenceAttribute.self] = 0.42
        let evidence = DictationRecognitionEvidence.make(text: primary, alternatives: [
            primary, AttributedString("Відкрий Телеграм"), AttributedString("Відкрий Телеграм")
        ])
        #expect(evidence.primaryTranscript == "Відкрий Telegram")
        #expect(evidence.alternativeTranscripts == ["Відкрий Телеграм"])
        #expect(evidence.averageSegmentConfidence == 0.42)
        let absent = DictationRecognitionEvidence.make(text: AttributedString("Текст"), alternatives: [])
        #expect(absent.averageSegmentConfidence == nil)
        #expect(absent.alternativeTranscripts.isEmpty)
    }

    @Test func evidenceIsPublishedBeforeFinalWithoutChangingPrimary() async {
        let backend = ControlledDictationSession()
        let controller = VoiceInputController(dictationBackendFactory: { backend })
        var received: [VoiceInputEvent] = []
        controller.setEventHandler { received.append($0) }
        await controller.start()
        let evidence = VoiceRecognitionEvidence(primaryTranscript: "Відкрий",
            alternativeTranscripts: ["Відкрий Telegram"], segmentAlternativeCount: 0, averageSegmentConfidence: 0.3)
        backend.event?(.evidence(evidence)); backend.event?(.final(evidence.primaryTranscript))
        #expect(received.suffix(3) == [.recognitionEvidence(evidence), .ios27AppleTranscript("Відкрий", isFinal: true), .state(.idle)])
    }
}
