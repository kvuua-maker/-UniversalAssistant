import AVFoundation
import Observation
import OSLog
import Speech
import UIKit

enum VoiceInputState: Equatable, Sendable { case idle, requestingPermission, listening, transcribing, denied, unavailable, failed }

enum VoiceInputEvent: Equatable, Sendable {
    case state(VoiceInputState)
    case recognitionEvidence(VoiceRecognitionEvidence)
    case transcript(String, isFinal: Bool)
}

@MainActor
protocol VoiceInputControlling: AnyObject {
    var engineIdentifier: String { get }
    var state: VoiceInputState { get }
    var transcript: String { get }
    func start(locale: Locale) async
    func stop(reason: VoiceStopReason)
    func setEventHandler(_ handler: @escaping @MainActor @Sendable (VoiceInputEvent) -> Void)
}

struct VoiceRecognitionEvidence: Equatable, Sendable {
    let primaryTranscript: String
    let alternativeTranscripts: [String]
    let segmentAlternativeTranscripts: [String]
    let partialTranscriptHistory: [String]
    let segmentAlternativeCount: Int
    let averageSegmentConfidence: Double?

    init(
        primaryTranscript: String,
        alternativeTranscripts: [String],
        segmentAlternativeTranscripts: [String] = [],
        partialTranscriptHistory: [String] = [],
        segmentAlternativeCount: Int,
        averageSegmentConfidence: Double?
    ) {
        self.primaryTranscript = primaryTranscript
        self.alternativeTranscripts = alternativeTranscripts
        self.segmentAlternativeTranscripts = segmentAlternativeTranscripts
        self.partialTranscriptHistory = partialTranscriptHistory
        self.segmentAlternativeCount = segmentAlternativeCount
        self.averageSegmentConfidence = averageSegmentConfidence
    }

    func withPartialTranscriptHistory(_ history: [String]) -> Self {
        .init(
            primaryTranscript: primaryTranscript,
            alternativeTranscripts: alternativeTranscripts,
            segmentAlternativeTranscripts: segmentAlternativeTranscripts,
            partialTranscriptHistory: history,
            segmentAlternativeCount: segmentAlternativeCount,
            averageSegmentConfidence: averageSegmentConfidence
        )
    }
}

/// Converts Apple's segment-scoped alternatives into bounded whole-command
/// hypotheses. It only substitutes text returned by Speech at Apple's exact
/// UTF-16 range; it never invents a word or an entity mapping.
enum VoiceRecognitionCandidateBuilder {
    static let maximumWholeTranscriptions = 8
    static let maximumSegmentTranscriptions = 16
    static let maximumPartialHistory = 16

    static func segmentAlternativeTranscripts(
        primaryTranscript: String,
        segments: [SFTranscriptionSegment],
        limit: Int = maximumSegmentTranscriptions
    ) -> [String] {
        replacingSegmentAlternatives(
            in: primaryTranscript,
            alternatives: segments.map { ($0.substringRange, $0.alternativeSubstrings) },
            limit: limit
        )
    }

    static func replacingSegmentAlternatives(
        in primaryTranscript: String,
        alternatives: [(range: NSRange, values: [String])],
        limit: Int = maximumSegmentTranscriptions
    ) -> [String] {
        guard limit > 0 else { return [] }
        let source = primaryTranscript as NSString
        var seen = Set([comparisonKey(primaryTranscript)])
        var output: [String] = []
        for item in alternatives {
            guard item.range.location != NSNotFound,
                  item.range.location >= 0,
                  item.range.length >= 0,
                  item.range.location + item.range.length <= source.length else { continue }
            for value in item.values {
                let replacement = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !replacement.isEmpty else { continue }
                let candidate = source.replacingCharacters(in: item.range, with: replacement)
                let key = comparisonKey(candidate)
                guard !key.isEmpty, seen.insert(key).inserted else { continue }
                output.append(candidate)
                if output.count == limit { return output }
            }
        }
        return output
    }

    static func appendingPartial(
        _ transcript: String,
        to history: inout [String],
        limit: Int = maximumPartialHistory
    ) {
        let value = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard limit > 0, !value.isEmpty else { return }
        let key = comparisonKey(value)
        guard history.last.map(comparisonKey) != key else { return }
        history.append(value)
        if history.count > limit { history.removeFirst(history.count - limit) }
    }

    private static func comparisonKey(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "uk_UA")
        ).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

enum VoiceTranscriptEvidenceSource: String, Equatable, Sendable {
    case primary, wholeAlternative, segmentAlternative, partialHistory
}

struct StabilizedVoiceTranscript: Equatable, Sendable {
    let text: String
    let source: VoiceTranscriptEvidenceSource
}

/// Selects a complete command only from text Apple Speech actually returned.
/// It never inserts a registry value into the transcript. A non-primary
/// hypothesis may win only when it conservatively extends the primary command,
/// or when Apple's candidate contains stronger exact request vocabulary while
/// retaining the rest of the utterance.
enum VoiceTranscriptStabilizer {
    private struct Candidate {
        let text: String
        let source: VoiceTranscriptEvidenceSource
    }

    static func stabilize(
        _ evidence: VoiceRecognitionEvidence,
        contextualVocabulary: [String]
    ) -> StabilizedVoiceTranscript {
        let primary = normalizedForDisplay(evidence.primaryTranscript)
        guard !primary.isEmpty else {
            return .init(text: "", source: .primary)
        }
        let candidates = uniqueCandidates(evidence, excluding: primary)
        let primaryTokens = tokens(primary)
        let vocabulary = contextualVocabulary
            .map(normalizedForComparison)
            .filter { !$0.isEmpty }
        let primaryMatches = vocabularyMatchCount(primary, vocabulary: vocabulary)

        var selected = Candidate(text: primary, source: .primary)
        var selectedMatches = primaryMatches
        var selectedTokenCount = primaryTokens.count

        for candidate in candidates {
            let candidateTokens = tokens(candidate.text)
            guard !candidateTokens.isEmpty else { continue }
            let matches = vocabularyMatchCount(candidate.text, vocabulary: vocabulary)
            let primaryIsSubsequence = isOrderedSubsequence(primaryTokens, of: candidateTokens)
            let conservativelyExtendsPrimary = primaryIsSubsequence && candidateTokens.count > primaryTokens.count
            let overlap = tokenOverlap(primaryTokens, candidateTokens)
            let hasStrongerVocabularyEvidence = matches > primaryMatches && overlap >= 0.5
            guard conservativelyExtendsPrimary || hasStrongerVocabularyEvidence else { continue }

            let shouldSelect = matches > selectedMatches ||
                (matches == selectedMatches && candidateTokens.count > selectedTokenCount) ||
                (matches == selectedMatches && candidateTokens.count == selectedTokenCount &&
                    sourcePriority(candidate.source) > sourcePriority(selected.source))
            if shouldSelect {
                selected = candidate
                selectedMatches = matches
                selectedTokenCount = candidateTokens.count
            }
        }
        return .init(text: selected.text, source: selected.source)
    }

    static func normalizedForDisplay(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func uniqueCandidates(
        _ evidence: VoiceRecognitionEvidence,
        excluding primary: String
    ) -> [Candidate] {
        var seen = Set([normalizedForComparison(primary)])
        var output: [Candidate] = []
        func append(_ values: [String], source: VoiceTranscriptEvidenceSource) {
            for raw in values {
                let value = normalizedForDisplay(raw)
                let key = normalizedForComparison(value)
                guard !key.isEmpty, seen.insert(key).inserted else { continue }
                output.append(.init(text: value, source: source))
            }
        }
        append(evidence.alternativeTranscripts, source: .wholeAlternative)
        append(evidence.segmentAlternativeTranscripts, source: .segmentAlternative)
        append(Array(evidence.partialTranscriptHistory.suffix(4).reversed()), source: .partialHistory)
        return output
    }

    private static func normalizedForComparison(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "uk_UA")
        ).split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
    }

    private static func tokens(_ value: String) -> [String] {
        normalizedForComparison(value).split(separator: " ").map(String.init)
    }

    private static func vocabularyMatchCount(_ value: String, vocabulary: [String]) -> Int {
        let comparable = normalizedForComparison(value)
        let joined = comparable.replacingOccurrences(of: " ", with: "")
        return vocabulary.reduce(into: 0) { count, phrase in
            let bounded = " \(comparable) ".contains(" \(phrase) ")
            let compact = phrase.count >= 4 && joined.contains(phrase.replacingOccurrences(of: " ", with: ""))
            if bounded || compact { count += 1 }
        }
    }

    private static func isOrderedSubsequence(_ smaller: [String], of larger: [String]) -> Bool {
        guard !smaller.isEmpty, smaller.count <= larger.count else { return false }
        var index = larger.startIndex
        for token in smaller {
            guard let match = larger[index...].firstIndex(of: token) else { return false }
            index = larger.index(after: match)
        }
        return true
    }

    private static func tokenOverlap(_ lhs: [String], _ rhs: [String]) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let left = lhs.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        let right = rhs.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        let common = left.reduce(0) { $0 + min($1.value, right[$1.key, default: 0]) }
        return Double(common) / Double(max(lhs.count, rhs.count))
    }

    private static func sourcePriority(_ value: VoiceTranscriptEvidenceSource) -> Int {
        switch value {
        case .primary: 4
        case .wholeAlternative: 3
        case .segmentAlternative: 2
        case .partialHistory: 1
        }
    }
}

enum VoiceStopReason: String, Sendable {
    case sessionRestart, externalRequest, userPressedStop, voiceDisabled, sceneInactive
    case recognitionFinal, recognitionError, audioInterruption, routeChange, startFailure
}

private enum VoiceDiagnostic {
    static let logger = Logger(subsystem: "com.universalassistant.app", category: "VoicePipeline")
}

final class DiagnosticCommandAudioRecorder: @unchecked Sendable {
    struct Completion: Sendable {
        let relativePath: String?
        let truncated: Bool
        let byteCount: Int
        let durationMilliseconds: Int
    }

    private let queue = DispatchQueue(label: "com.universalassistant.diagnostics.command-audio", qos: .utility)
    private let localStore: PhysicalDiagnosticLocalStore
    private let maximumDurationSeconds: Double
    private var requestID: UUID?
    private var destination: URL?
    private var file: AVAudioFile?
    private var writtenFrames: AVAudioFramePosition = 0
    private var truncated = false
    private var recordedDurationSeconds: Double = 0

    init(localStore: PhysicalDiagnosticLocalStore, maximumDurationSeconds: Double = 45) {
        self.localStore = localStore
        self.maximumDurationSeconds = maximumDurationSeconds
    }

    func start(requestID: UUID) {
        queue.sync {
            file = nil
            self.requestID = requestID
            destination = localStore.diagnosticAudioURL(for: requestID)
            writtenFrames = 0
            truncated = false
            recordedDurationSeconds = 0
            if let destination { try? FileManager.default.removeItem(at: destination) }
        }
    }

    func appendSameSpeechBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let copy = Self.copy(buffer) else { return }
        queue.async { [weak self] in self?.write(copy) }
    }

    func finish() -> Completion {
        queue.sync {
            file = nil
            let relativePath = requestID.map { localStore.diagnosticAudioRelativePath(for: $0) }
            let byteCount = destination.flatMap {
                (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            } ?? 0
            requestID = nil
            destination = nil
            writtenFrames = 0
            let durationMilliseconds = max(0, Int((recordedDurationSeconds * 1_000).rounded()))
            let result = Completion(
                relativePath: byteCount > 0 ? relativePath : nil,
                truncated: truncated,
                byteCount: byteCount,
                durationMilliseconds: durationMilliseconds
            )
            truncated = false
            recordedDurationSeconds = 0
            return result
        }
    }

    private func write(_ buffer: AVAudioPCMBuffer) {
        guard requestID != nil, let destination else { return }
        let maximumFrames = AVAudioFramePosition(buffer.format.sampleRate * maximumDurationSeconds)
        guard writtenFrames < maximumFrames else {
            truncated = true
            return
        }
        if file == nil {
            do {
                file = try AVAudioFile(forWriting: destination, settings: buffer.format.settings)
                try? FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                    ofItemAtPath: destination.path
                )
            } catch {
                file = nil
                return
            }
        }
        let remaining = maximumFrames - writtenFrames
        if AVAudioFramePosition(buffer.frameLength) > remaining {
            buffer.frameLength = AVAudioFrameCount(max(0, remaining))
            truncated = true
        }
        guard buffer.frameLength > 0 else { return }
        do {
            try file?.write(from: buffer)
            writtenFrames += AVAudioFramePosition(buffer.frameLength)
            recordedDurationSeconds += Double(buffer.frameLength) / buffer.format.sampleRate
        } catch {
            file = nil
        }
    }

    private static func copy(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let destination = AVAudioPCMBuffer(
            pcmFormat: source.format,
            frameCapacity: source.frameLength
        ) else { return nil }
        destination.frameLength = source.frameLength
        let sourceBuffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: source.audioBufferList)
        )
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(destination.mutableAudioBufferList)
        guard sourceBuffers.count == destinationBuffers.count else { return nil }
        for index in sourceBuffers.indices {
            let sourceBuffer = sourceBuffers[index]
            guard let sourceData = sourceBuffer.mData,
                  let destinationData = destinationBuffers[index].mData else { return nil }
            let byteCount = min(Int(sourceBuffer.mDataByteSize), Int(destinationBuffers[index].mDataByteSize))
            memcpy(destinationData, sourceData, byteCount)
            destinationBuffers[index].mDataByteSize = UInt32(byteCount)
        }
        return destination
    }
}


final class LocalVoiceDiagnosticReport: @unchecked Sendable {
    struct Entry: Codable, Sendable {
        let timestamp: Date
        let marker: String
        let details: String
        var textPayload: String? = nil
    }
    private struct LegacyPersisted: Codable { let sessionID: UUID; let startedAt: Date; let entries: [Entry] }
    static let shared = LocalVoiceDiagnosticReport()
    private let lock = NSLock()
    private var entries: [Entry] = []
    private let diagnosticSessionID = UUID()
    private var requestID = UUID()
    private var requestGeneration: UInt64 = 0
    private var startedAt = Date()
    private var finalSpeechTranscript: String?
    private var normalizedTranscript: String?
    private var explicitTerminalState: DiagnosticTerminalState?
    private var interactiveContinuationPending = false
    private let defaults: UserDefaults
    private let persistenceKey: String
    private let localStore: PhysicalDiagnosticLocalStore
    private let crashlyticsRecorder: any CrashlyticsDiagnosticRecording
    private let audioRecorder: DiagnosticCommandAudioRecorder
    private var legacyRecovered: LegacyPersisted?
    private static let maximumDeliveredEvents = 250
    private static let detailedConsentKey = "build32-detailed-diagnostics-consent"
    private static let safeAttributeKeys: Set<String> = [
        "state", "granted", "available", "locale", "input", "sample_rate", "channels", "running", "count", "frames",
        "partial_results", "punctuation", "task_hint", "api", "has_text", "final", "error_domain", "error_code",
        "partial_count", "final_count", "reason", "had_task", "had_request", "length", "input_available", "error_type",
        "status", "capability", "language", "mechanism", "kind", "alternatives", "segment_alternatives", "confidence_bucket",
        "context_count", "on_device_supported", "on_device_required", "generation", "source", "selected", "domain", "candidate_count",
        "confidence", "confidence_margin", "object", "action", "destination", "service", "app", "date", "time", "duration",
        "constraint_count", "target", "person", "location", "constraints", "candidate_fingerprints",
        "contact_identifier_hash", "photo_asset_id_hash", "url_host_class", "coarse_location_role", "ocr_block_count", "ocr_confidence",
        "input_type", "output_type", "permission", "terminal", "stage", "last_stage", "last_pre", "last_post",
        "missing_expected_post", "http_status", "schema", "detailed", "scheme", "operation", "provider", "route", "result",
        "parameter", "pages", "type", "accepted", "confirmed", "elapsed_ms", "fallback",
        "location_source", "input_count", "output_count", "nearest_m_bucket", "radius_m"
    ]

    init(
        defaults: UserDefaults = .standard,
        persistenceKey: String = "physical-diagnostic-active-request-v1",
        localStore: PhysicalDiagnosticLocalStore = .shared,
        crashlyticsRecorder: any CrashlyticsDiagnosticRecording = CrashlyticsDiagnosticBridge.shared
    ) {
        self.defaults = defaults
        self.persistenceKey = persistenceKey
        self.localStore = localStore
        self.audioRecorder = DiagnosticCommandAudioRecorder(localStore: localStore)
        self.crashlyticsRecorder = crashlyticsRecorder
        if let data = defaults.data(forKey: persistenceKey),
           let value = try? JSONDecoder().decode(LegacyPersisted.self, from: data) {
            legacyRecovered = value
        }
    }

    var diagnosticSessionIdentifier: UUID { diagnosticSessionID }

    var detailedDiagnosticsEnabled: Bool {
        get { defaults.bool(forKey: Self.detailedConsentKey) }
        set { defaults.set(newValue, forKey: Self.detailedConsentKey) }
    }
    var currentRequestIdentifier: UUID {
        lock.withLock { requestID }
    }

    func beginCommandAudioRecording() {
        let identity = lock.withLock { (requestID, detailedDiagnosticsEnabled) }
        guard identity.1 else { return }
        audioRecorder.start(requestID: identity.0)
        let relativePath = localStore.diagnosticAudioRelativePath(for: identity.0)
        localStore.updateActive(
            sequence: lock.withLock { entries.count },
            stage: "diagnostic_audio_started",
            diagnosticAudioRelativePath: relativePath,
            diagnosticAudioTruncated: false
        )
        record("diagnostic_audio_started", "status=recording")
    }

    func appendCommandAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard detailedDiagnosticsEnabled else { return }
        audioRecorder.appendSameSpeechBuffer(buffer)
    }

    func finishCommandAudioRecording(reason: VoiceStopReason) {
        let completion = audioRecorder.finish()
        guard let relativePath = completion.relativePath else { return }
        localStore.updateActive(
            sequence: lock.withLock { entries.count },
            stage: "diagnostic_audio_finished",
            diagnosticAudioRelativePath: relativePath,
            diagnosticAudioTruncated: completion.truncated,
            diagnosticAudioDurationMilliseconds: completion.durationMilliseconds
        )
        record(
            "diagnostic_audio_finished",
            "status=saved reason=\(reason.rawValue) length=\(completion.byteCount) truncated=\(completion.truncated)"
        )
    }


    func reset() {
        lock.lock()
        entries = []
        requestID = UUID()
        requestGeneration = 0
        startedAt = .now
        finalSpeechTranscript = nil
        normalizedTranscript = nil
        explicitTerminalState = nil
        interactiveContinuationPending = false
        beginDurableRequestLocked()
        lock.unlock()
    }

    func beginHomeRequest(generation: UInt64 = 0) {
        lock.lock()
        let latestVoiceIngress = entries.lastIndex(where: { $0.marker == "transcript_delivered_to_router" })
        let latestHomeRequest = entries.lastIndex(where: { $0.marker == "home_request_started" })
        let hasFreshVoiceIngress = latestVoiceIngress.map { voiceIndex in
            latestHomeRequest.map { voiceIndex > $0 } ?? true
        } ?? false
        if !hasFreshVoiceIngress {
            entries = []
            requestID = UUID()
            startedAt = .now
            finalSpeechTranscript = nil
            normalizedTranscript = nil
            explicitTerminalState = nil
            interactiveContinuationPending = false
        }
        requestGeneration = generation
        beginDurableRequestLocked()
        appendLocked("request_created", "source=home generation=\(generation)", durable: true)
        appendLocked("home_request_started", "source=home generation=\(generation)", durable: true)
        lock.unlock()
    }

    func record(_ marker: String, _ details: String = "") {
        let safeDetails = Self.privacySafeDetails(details)
        lock.lock()
        // Scene, MetricKit, and other ambient callbacks can arrive while no
        // command is active. They must not manufacture a crash-suspected Home
        // request. Real voice and typed requests create the durable snapshot in
        // reset()/beginHomeRequest() before their first command marker.
        if localStore.activeSnapshot() != nil {
            appendLocked(marker, safeDetails, durable: marker.hasSuffix("_PRE") || marker == "request_created")
        }
        lock.unlock()
        VoiceDiagnostic.logger.notice("\(marker, privacy: .public) \(safeDetails, privacy: .public)")
    }

    func recordBoundaryPre(_ boundary: String, _ details: String = "") {
        record("\(boundary)_PRE", details)
    }

    func recordBoundaryPost(_ boundary: String, _ details: String = "") {
        record("\(boundary)_POST", details)
    }

    private func recordPartialSpeechTranscript(_ transcript: String) {
        lock.lock()
        let detailed = detailedDiagnosticsEnabled
        let safeTranscript = Self.privacySafeTranscript(transcript)
        appendLocked(
            "partial_transcript",
            "length=\(transcript.count) detailed=\(detailed)",
            durable: true,
            textPayload: detailed ? safeTranscript : nil
        )
        crashlyticsRecorder.recordPartialTranscript(
            transcript,
            sequence: entries.count,
            identity: crashlyticsIdentityLocked(),
            detailedDiagnosticsEnabled: detailed
        )
        if detailed {
            localStore.updateActive(
                sequence: entries.count,
                stage: "partial_transcript",
                detailedDiagnosticsConsent: true,
                latestPartialTranscript: safeTranscript
            )
        }
        lock.unlock()
    }

    func recordSpeechTranscript(_ transcript: String, isFinal: Bool) {
        guard isFinal else {
            recordPartialSpeechTranscript(transcript)
            return
        }
        lock.lock()
        finalSpeechTranscript = Self.privacySafeTranscript(transcript)
        appendLocked(
            "final_transcript",
            "length=\(transcript.count) detailed=\(detailedDiagnosticsEnabled)",
            durable: true,
            textPayload: detailedDiagnosticsEnabled ? finalSpeechTranscript : nil
        )
        crashlyticsRecorder.recordTranscript(
            transcript,
            normalized: false,
            sequence: entries.count,
            identity: crashlyticsIdentityLocked(),
            detailedDiagnosticsEnabled: detailedDiagnosticsEnabled
        )
        if detailedDiagnosticsEnabled {
            localStore.updateActive(
                sequence: entries.count,
                stage: "final_transcript",
                detailedDiagnosticsConsent: true,
                finalSpeechTranscript: finalSpeechTranscript
            )
        }
        lock.unlock()
    }

    func recordSubmittedInputIfNeeded(_ transcript: String) {
        lock.lock()
        guard finalSpeechTranscript == nil else {
            lock.unlock()
            return
        }
        finalSpeechTranscript = Self.privacySafeTranscript(transcript)
        appendLocked(
            "input_transcript",
            "length=\(transcript.count) detailed=\(detailedDiagnosticsEnabled)",
            durable: true,
            textPayload: detailedDiagnosticsEnabled ? finalSpeechTranscript : nil
        )
        crashlyticsRecorder.recordTranscript(
            transcript,
            normalized: false,
            sequence: entries.count,
            identity: crashlyticsIdentityLocked(),
            detailedDiagnosticsEnabled: detailedDiagnosticsEnabled
        )
        if detailedDiagnosticsEnabled {
            localStore.updateActive(
                sequence: entries.count,
                stage: "input_transcript",
                detailedDiagnosticsConsent: true,
                finalSpeechTranscript: finalSpeechTranscript
            )
        }
        lock.unlock()
    }

    func recordNormalizedTranscript(_ transcript: String) {
        lock.lock()
        normalizedTranscript = Self.privacySafeTranscript(transcript)
        appendLocked(
            "normalization",
            "length=\(transcript.count) detailed=\(detailedDiagnosticsEnabled)",
            durable: true,
            textPayload: detailedDiagnosticsEnabled ? normalizedTranscript : nil
        )
        crashlyticsRecorder.recordTranscript(
            transcript,
            normalized: true,
            sequence: entries.count,
            identity: crashlyticsIdentityLocked(),
            detailedDiagnosticsEnabled: detailedDiagnosticsEnabled
        )
        if detailedDiagnosticsEnabled {
            localStore.updateActive(
                sequence: entries.count,
                stage: "normalization",
                detailedDiagnosticsConsent: true,
                normalizedTranscript: normalizedTranscript
            )
        }
        lock.unlock()
    }

    func recordTerminal(_ state: DiagnosticTerminalState, details: String = "") {
        lock.lock()
        guard explicitTerminalState == nil else { lock.unlock(); return }
        explicitTerminalState = state
        appendLocked("terminal_request_state", "state=\(state.rawValue) \(details)", durable: true)
        localStore.updateActive(sequence: entries.count, stage: "terminal_request_state", terminal: state)
        lock.unlock()
    }

    func suspendForInteractiveContinuation(_ kind: String, generation: UInt64? = nil) {
        lock.lock()
        interactiveContinuationPending = true
        if let generation {
            requestGeneration = generation
            localStore.updateActive(sequence: entries.count, stage: "interactive_continuation_suspended", generation: generation)
        }
        appendLocked("interactive_continuation_suspended", "kind=\(String(kind.prefix(64))) generation=\(generation ?? requestGeneration)", durable: true)
        lock.unlock()
    }

    func resumeInteractiveContinuation(generation: UInt64? = nil) {
        lock.lock()
        guard interactiveContinuationPending else { lock.unlock(); return }
        interactiveContinuationPending = false
        if let generation {
            requestGeneration = generation
            localStore.updateActive(sequence: entries.count, stage: "interactive_continuation_resumed", generation: generation)
        }
        appendLocked("interactive_continuation_resumed", "generation=\(generation ?? requestGeneration)", durable: true)
        lock.unlock()
    }

    @discardableResult
    func finishInteractiveContinuation(_ state: DiagnosticTerminalState, details: String = "") -> Bool {
        lock.lock()
        guard interactiveContinuationPending, explicitTerminalState == nil else { lock.unlock(); return false }
        interactiveContinuationPending = false
        explicitTerminalState = state
        appendLocked("interactive_continuation_finished", "state=\(state.rawValue) \(details)", durable: true)
        appendLocked("terminal_request_state", "state=\(state.rawValue)", durable: true)
        localStore.updateActive(sequence: entries.count, stage: "terminal_request_state", terminal: state)
        lock.unlock()
        return true
    }

    func snapshot() -> String {
        lock.lock(); defer { lock.unlock() }
        let lines = entries.enumerated().map { "\($0.offset + 1). \($0.element.marker)\($0.element.details.isEmpty ? "" : " | \($0.element.details)")" }
        return (["UniversalAssistant Local Diagnostic Black Box", "Command audio is local-only until Firebase Storage is configured."] + lines).joined(separator: "\n")
    }

    @MainActor func recoveredIncompleteSession() -> PhysicalDiagnosticSession? {
        lock.lock(); defer { lock.unlock() }
        if let active = localStore.consumeUncleanActiveRequest() {
            let missing = active.lastPRE.flatMap { pre in
                let expected = DiagnosticAnomalyAnalyzer.pairedPost(for: pre)
                return expected == active.lastPOST ? nil : expected
            }
            let anomaly = DiagnosticAnomaly(
                anomalyClass: .uncleanTermination,
                certainty: .probableFailureBoundary,
                stage: active.lastPRE ?? active.lastStage,
                reason: missing.map { "missing_expected_post:\($0)" } ?? "request_not_terminal"
            )
            localStore.setLastAnomaly(anomaly)
            let now = Date()
            var uncleanEvent = PhysicalDiagnosticEvent(
                sequence: 1, timestamp: now, marker: "unclean_termination_detected",
                attributes: [
                    "last_stage": active.lastStage,
                    "last_pre": active.lastPRE ?? "none",
                    "last_post": active.lastPOST ?? "none",
                    "missing_expected_post": missing ?? "unknown"
                ]
            )
            uncleanEvent.diagnosticSessionID = active.diagnosticSessionID
            uncleanEvent.requestID = active.requestID
            uncleanEvent.requestGeneration = active.requestGeneration
            uncleanEvent.build = active.build
            let prior = localStore.events(for: active.requestID)
            let preserved = (prior + [uncleanEvent]).suffix(Self.maximumDeliveredEvents)
            var events = preserved.enumerated().map { index, source in
                PhysicalDiagnosticEvent(
                    sequence: index + 1,
                    timestamp: source.timestamp,
                    marker: source.marker,
                    attributes: source.attributes,
                    diagnosticSessionID: active.diagnosticSessionID,
                    requestID: active.requestID,
                    requestGeneration: active.requestGeneration,
                    build: active.build,
                    textPayload: source.textPayload
                )
            }
            let terminalEvent = PhysicalDiagnosticEvent(
                sequence: events.count + 1, timestamp: now, marker: "terminal_request_state",
                attributes: ["state": DiagnosticTerminalState.error.rawValue],
                diagnosticSessionID: active.diagnosticSessionID, requestID: active.requestID,
                requestGeneration: active.requestGeneration, build: active.build
            )
            let requestEndEvent = PhysicalDiagnosticEvent(
                sequence: events.count + 2, timestamp: now, marker: "request_end",
                attributes: ["terminal": DiagnosticTerminalState.error.rawValue],
                diagnosticSessionID: active.diagnosticSessionID, requestID: active.requestID,
                requestGeneration: active.requestGeneration, build: active.build
            )
            events.append(terminalEvent)
            events.append(requestEndEvent)
            localStore.append(uncleanEvent, durable: true)
            localStore.append(terminalEvent, durable: true)
            localStore.append(requestEndEvent, durable: true)
            let recoveredStart = events.first?.timestamp ?? active.updatedAt
            let recoveredFeature = events.contains {
                ["start_listening_invoked", "diagnostic_audio_started", "diagnostic_audio_finished"].contains($0.marker)
            } ? "voice" : "request"
            var session = PhysicalDiagnosticSession(
                schema: 2, sessionID: active.requestID, liveTestID: "BUILD32-PRODUCTION-BLACK-BOX", feature: recoveredFeature,
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                build: active.build, environment: "internal-testflight", osVersion: UIDevice.current.systemVersion,
                deviceClass: UIDevice.current.model, startedAt: recoveredStart, endedAt: now,
                durationMilliseconds: max(0, Int(now.timeIntervalSince(recoveredStart) * 1_000)),
                result: .crashSuspected, failureStage: anomaly.stage,
                errorDomain: "ProcessTerminatedBeforeTerminalResult", errorCode: -1, events: events
            )
            session.diagnosticSessionID = active.diagnosticSessionID
            session.requestID = active.requestID
            session.requestGeneration = active.requestGeneration
            session.terminalState = .error
            session.detailedDiagnosticsConsent = active.detailedDiagnosticsConsent
            session.finalSpeechTranscript = active.detailedDiagnosticsConsent ? active.finalSpeechTranscript : nil
            session.normalizedTranscript = active.detailedDiagnosticsConsent ? active.normalizedTranscript : nil
            session.diagnosticAudioRelativePath = active.diagnosticAudioRelativePath
            session.diagnosticAudioTruncated = active.diagnosticAudioTruncated
            session.anomaly = anomaly
            session.diagnosticAudioDurationMilliseconds = active.diagnosticAudioDurationMilliseconds
            localStore.addPending(Self.queued(session))
            crashlyticsRecorder.recordRecoveredUncleanSession(session)
            crashlyticsRecorder.recordTerminal(session)
            return session
        }
        guard let value = legacyRecovered, !value.entries.isEmpty else { return nil }
        legacyRecovered = nil
        defaults.removeObject(forKey: persistenceKey)
        let bounded = Self.boundedForDelivery(value.entries)
        let events = bounded.enumerated().map { index, entry in
            PhysicalDiagnosticEvent(sequence: index + 1, timestamp: entry.timestamp, marker: entry.marker, attributes: [:])
        }
        let ended = value.entries.last?.timestamp ?? value.startedAt
        return .init(schema: 1, sessionID: value.sessionID, liveTestID: "MS-800-RECOVERED-REQUEST", feature: "request",
                     appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                     build: Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0,
                     environment: "internal-testflight", osVersion: UIDevice.current.systemVersion, deviceClass: UIDevice.current.model,
                     startedAt: value.startedAt, endedAt: ended, durationMilliseconds: max(0, Int(ended.timeIntervalSince(value.startedAt) * 1_000)),
                     result: .failure, failureStage: value.entries.last?.marker,
                     errorDomain: "ProcessTerminatedBeforeTerminalResult", errorCode: -1, events: events)
    }

    @MainActor func completedSession() -> PhysicalDiagnosticSession? {
        lock.lock(); defer { lock.unlock() }
        guard !interactiveContinuationPending,
              entries.contains(where: { ["start_listening_invoked", "home_request_started"].contains($0.marker) }),
              !entries.contains(where: { $0.marker == "request_end" }),
              let terminalState = explicitTerminalState ?? inferredTerminalStateLocked() else { return nil }
        if !entries.contains(where: { $0.marker == "terminal_request_state" }) {
            appendLocked("terminal_request_state", "state=\(terminalState.rawValue)", durable: true)
            localStore.updateActive(sequence: entries.count, stage: "terminal_request_state", terminal: terminalState)
        }
        appendLocked("request_end", "terminal=\(terminalState.rawValue)", durable: true)
        let bounded = Self.boundedForDelivery(entries)
        let events = bounded.enumerated().map { index, entry in
            PhysicalDiagnosticEvent(
                sequence: index + 1,
                timestamp: entry.timestamp,
                marker: entry.marker,
                attributes: Self.privacySafeAttributes(entry.details),
                textPayload: entry.textPayload
            )
        }
        let error = events.reversed().first {
            let domain = $0.attributes["error_domain"]
            let code = $0.attributes["error_code"].flatMap(Int.init) ?? 0
            return (domain != nil && domain != "none") || code != 0
        }
        let result: PhysicalDiagnosticResult = terminalState == .success ? .success : (terminalState == .cancelled ? .interrupted : .failure)
        let ended = entries.last?.timestamp ?? .now
        let consent = detailedDiagnosticsEnabled
        var session = PhysicalDiagnosticSession(
            schema: 2, sessionID: requestID, liveTestID: "BUILD32-PRODUCTION-BLACK-BOX",
            feature: entries.contains(where: { $0.marker == "start_listening_invoked" }) ? "voice" : "request",
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            build: Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0,
            environment: "internal-testflight", osVersion: UIDevice.current.systemVersion, deviceClass: UIDevice.current.model,
            startedAt: startedAt, endedAt: ended, durationMilliseconds: max(0, Int(ended.timeIntervalSince(startedAt) * 1_000)),
            result: result,
            failureStage: terminalState == .success ? nil : (error?.marker ?? events.reversed().first(where: {
                !["terminal_request_state", "request_end"].contains($0.marker)
            })?.marker),
            errorDomain: error?.attributes["error_domain"], errorCode: error?.attributes["error_code"].flatMap(Int.init), events: events
        )
        session.diagnosticSessionID = diagnosticSessionID
        session.requestID = requestID
        session.requestGeneration = requestGeneration
        session.terminalState = terminalState
        session.detailedDiagnosticsConsent = consent
        session.finalSpeechTranscript = consent ? finalSpeechTranscript : nil
        session.normalizedTranscript = consent ? normalizedTranscript : nil
        let active = localStore.activeSnapshot()
        session.diagnosticAudioRelativePath = active?.diagnosticAudioRelativePath
        session.diagnosticAudioTruncated = active?.diagnosticAudioTruncated
        session.anomaly = DiagnosticAnomalyAnalyzer.analyze(events: events)
        if let anomaly = session.anomaly { localStore.setLastAnomaly(anomaly) }
        session.diagnosticAudioDurationMilliseconds = active?.diagnosticAudioDurationMilliseconds
        CloudKitDiagnosticAudioDelivery.persistPending(session, localStore: localStore)
        localStore.addPending(Self.queued(session))
        localStore.updateActive(sequence: entries.count, stage: "request_end", terminal: terminalState)
        localStore.clearTerminalActiveRequest()
        defaults.removeObject(forKey: persistenceKey)
        crashlyticsRecorder.recordTerminal(session)
        return session
    }

    private func appendLocked(_ marker: String, _ details: String, durable: Bool, textPayload: String? = nil) {
        let safeDetails = Self.privacySafeDetails(details)
        let entry = Entry(timestamp: .now, marker: marker, details: safeDetails, textPayload: textPayload)
        entries.append(entry)
        if entries.count > 1_000 { entries.removeFirst(entries.count - 1_000) }
        let attributes = Self.privacySafeAttributes(safeDetails)
        var event = PhysicalDiagnosticEvent(sequence: entries.count, timestamp: entry.timestamp, marker: marker, attributes: attributes)
        event.textPayload = textPayload
        event.diagnosticSessionID = diagnosticSessionID
        event.requestID = requestID
        event.requestGeneration = requestGeneration
        event.build = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
        localStore.append(event, durable: durable)
        localStore.updateActive(
            sequence: entries.count, stage: marker,
            pre: marker.hasSuffix("_PRE") ? marker : nil,
            post: marker.hasSuffix("_POST") ? marker : nil,
            capability: attributes["capability"]
        )
        crashlyticsRecorder.recordEvent(
            marker,
            details: safeDetails,
            sequence: entries.count,
            identity: crashlyticsIdentityLocked()
        )
    }

    private func beginDurableRequestLocked() {
        let existing = localStore.activeSnapshot().flatMap { snapshot in
            snapshot.requestID == requestID ? snapshot : nil
        }
        let snapshot = DiagnosticActiveRequestSnapshot(
            diagnosticSessionID: diagnosticSessionID, requestID: requestID, requestGeneration: requestGeneration,
            build: Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0,
            eventSequence: entries.count, lastStage: entries.last?.marker ?? "REQUEST_CREATED", lastPRE: nil, lastPOST: nil,
            selectedCapability: nil, terminal: false, terminalState: nil,
            detailedDiagnosticsConsent: detailedDiagnosticsEnabled,
            latestPartialTranscript: existing?.latestPartialTranscript,
            finalSpeechTranscript: detailedDiagnosticsEnabled ? finalSpeechTranscript : nil,
            normalizedTranscript: detailedDiagnosticsEnabled ? normalizedTranscript : nil,
            diagnosticAudioRelativePath: existing?.diagnosticAudioRelativePath,
            diagnosticAudioTruncated: existing?.diagnosticAudioTruncated,
            updatedAt: .now
        )
        localStore.begin(snapshot)
        let inputMode = entries.contains(where: { ["start_listening_invoked", "final_transcript", "transcript_delivered_to_router"].contains($0.marker) }) ? "voice" : "unknown"
        crashlyticsRecorder.beginRequest(crashlyticsIdentityLocked(), inputMode: inputMode)
    }

    private func crashlyticsIdentityLocked() -> CrashlyticsDiagnosticRequestIdentity {
        CrashlyticsDiagnosticRequestIdentity(
            diagnosticSessionID: diagnosticSessionID,
            requestID: requestID,
            generation: requestGeneration,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            build: Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
        )
    }

    private func inferredTerminalStateLocked() -> DiagnosticTerminalState? {
        if entries.contains(where: { $0.marker == "visible_result" }) { return .success }
        if entries.contains(where: { $0.marker == "router_rejected" && $0.details.contains("clarification") }) { return .clarification }
        if entries.contains(where: { $0.marker == "execution_failed" && $0.details.contains("external_provider_required") }) { return .providerRequired }
        if entries.contains(where: { entry in
            let attributes = Self.parseAttributes(entry.details)
            let domain = attributes["error_domain"]
            let code = attributes["error_code"].flatMap(Int.init) ?? 0
            return (domain != nil && domain != "none") || code != 0 || entry.marker.hasSuffix("_failed")
        }) { return .error }
        if entries.contains(where: { $0.marker == "execution_failed" }) { return .error }
        if entries.contains(where: { $0.marker == "state_transition" && $0.details.contains("idle") }) { return .cancelled }
        return nil
    }

    private static func parseAttributes(_ details: String) -> [String: String] {
        Dictionary(uniqueKeysWithValues: details.split(separator: " ").compactMap { token in
            let parts = token.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[0].count <= 64 else { return nil }
            return (parts[0], String(parts[1].prefix(256)))
        })
    }

    private static func privacySafeAttributes(_ details: String) -> [String: String] {
        parseAttributes(details).reduce(into: [String: String]()) { output, item in
            guard safeAttributeKeys.contains(item.key) else { return }
            output[item.key] = privacySafeTranscript(item.value)
        }
    }

    private static func privacySafeDetails(_ details: String) -> String {
        privacySafeAttributes(details)
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
    }

    private static func privacySafeTranscript(_ value: String) -> String {
        var result = value.precomposedStringWithCanonicalMapping
        let patterns = [
            #"(?i)https?://\S+"#,
            #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            #"(?<!\d)\+?\d[\d\s()\-]{5,}\d(?!\d)"#,
            #"(?i)\b(?:bearer|token|password|пароль)\s*[:=]?\s*\S+"#
        ]
        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: "[REDACTED]", options: .regularExpression)
        }
        return result
    }

    private static func queued(_ session: PhysicalDiagnosticSession) -> DiagnosticQueuedUpload {
        .init(session: session, attempts: 0, expiresAt: Date().addingTimeInterval(7 * 86_400),
              nextAttemptAt: .now, status: .pendingUpload, lastHTTPStatus: nil, errorCategory: nil)
    }

    private static func boundedForDelivery(_ source: [Entry]) -> [Entry] {
        guard source.count > maximumDeliveredEvents else { return source }
        let ingressCount = 100
        return Array(source.prefix(ingressCount)) + Array(source.suffix(maximumDeliveredEvents - ingressCount))
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

final class VoiceSpeechActivityTracker: @unchecked Sendable {
    private let lock = NSLock()
    private let initialVoiceRMS: Float
    private let minimumAdaptiveRMS: Float
    private var noiseFloorRMS: Float
    private var lastVoiceUptime: TimeInterval?

    init(minimumRMS: Float = 0.002, minimumAdaptiveRMS: Float = 0.0004) {
        initialVoiceRMS = max(minimumRMS, minimumAdaptiveRMS)
        self.minimumAdaptiveRMS = max(0.0001, minimumAdaptiveRMS)
        noiseFloorRMS = max(0.0001, minimumAdaptiveRMS * 0.5)
    }

    func reset() {
        lock.lock()
        lastVoiceUptime = nil
        noiseFloorRMS = max(0.0001, minimumAdaptiveRMS * 0.5)
        lock.unlock()
    }

    func record(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0, let channels = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard channelCount > 0 else { return }
        var sumOfSquares: Float = 0
        for channel in 0..<channelCount {
            let samples = UnsafeBufferPointer(start: channels[channel], count: frameCount)
            for sample in samples { sumOfSquares += sample * sample }
        }
        let meanSquare = sumOfSquares / Float(frameCount * channelCount)
        let rms = sqrt(meanSquare)
        lock.lock()
        let adaptiveThreshold = max(
            minimumAdaptiveRMS,
            min(initialVoiceRMS, max(minimumAdaptiveRMS, noiseFloorRMS * 2.4))
        )
        if rms >= adaptiveThreshold {
            lastVoiceUptime = ProcessInfo.processInfo.systemUptime
        } else {
            noiseFloorRMS = (noiseFloorRMS * 0.94) + (rms * 0.06)
        }
        lock.unlock()
    }

    func hasRecentVoiceActivity(within interval: TimeInterval) -> Bool {
        lock.lock()
        let lastVoiceUptime = lastVoiceUptime
        lock.unlock()
        guard let lastVoiceUptime else { return false }
        return ProcessInfo.processInfo.systemUptime - lastVoiceUptime <= interval
    }
}


enum VoiceAudioCaptureError: Error, Equatable {
    case invalidInputFormat
}

/// Input-node taps must follow the format negotiated by the active hardware
/// route. Supplying a cached format is unsafe after a route/sample-rate change:
/// AVAudioEngine raises an Objective-C exception instead of a Swift error when
/// that format no longer matches. A nil install format asks AVFAudio to use the
/// freshly materialized input node's current format.
enum VoiceInputTapFormatPolicy {
    static func installationFormat(for activeFormat: AVAudioFormat) throws -> AVAudioFormat? {
        guard activeFormat.sampleRate > 0, activeFormat.channelCount > 0 else {
            throw VoiceAudioCaptureError.invalidInputFormat
        }
        return nil
    }
}

struct VoiceRecognitionRequestConfiguration: Sendable {
    static let maximumContextualStringCount = 100
    let contextualVocabulary: [String]
    let requireOnDeviceRecognition: Bool

    init(additionalVocabulary: [String] = [], requireOnDeviceRecognition: Bool = false) {
        contextualVocabulary = Self.boundedVocabulary(additional: additionalVocabulary)
        self.requireOnDeviceRecognition = requireOnDeviceRecognition
    }

    static var canonicalEntityVocabulary: [String] {
        let providers = OfficialPublicProviderHandoffRegistry.records.flatMap { provider in
            [provider.displayName] + preferredSpokenAlias(from: provider.aliases, excluding: provider.displayName)
        }
        let brands = CanonicalCatalogEntityRegistry.brandNames.flatMap { name in
            [name] + speechTransliterationVariants(for: name)
        }
        let applications = LaunchDeviceApplications.verified.flatMap { application in
            [application.id] + preferredSpokenAlias(from: application.aliases, excluding: application.id)
        }
        let services = MessengerKind.allCases.map(\.rawValue)
        return unique(providers + brands + applications + services)
    }

    /// Compact display-name-first vocabulary for local decoders with a strict
    /// prompt budget. This keeps every canonical provider, brand, app and
    /// service represented before request-scoped values are appended.
    static var canonicalWhisperVocabulary: [String] {
        let providers = OfficialPublicProviderHandoffRegistry.records.map(\.displayName)
        let brands = CanonicalCatalogEntityRegistry.brandNames
        let applications = LaunchDeviceApplications.verified.flatMap { application in
            [application.id] + preferredSpokenAlias(from: application.aliases, excluding: application.id)
        }
        let services = MessengerKind.allCases.map(\.rawValue)
        return unique(providers + brands + applications + services)
    }

    static var canonicalFunctionVocabulary: [String] {
        [
            "UniversalAssistant", "Apple Music", "подкаст", "календар",
            "нагадування", "маршрут", "погода", "контакт", "нотатка",
            "документ", "файл", "світлина", "будильник", "таймер",
            "QR-код", "QR code", "OCR", "відкрий", "запусти",
            "відскануй", "розпізнай", "знайди", "покажи", "проклади",
            "подзвони", "набери", "повідомлення", "переклади", "ліхтарик"
        ]
    }

    static var canonicalVocabulary: [String] {
        boundedVocabulary(
            additional: canonicalEntityVocabulary + canonicalFunctionVocabulary,
            includeCanonical: false
        )
    }

    static func boundedVocabulary(additional: [String], includeCanonical: Bool = true) -> [String] {
        var seen: Set<String> = []
        var output: [String] = []
        func append<S: Sequence>(_ source: S) where S.Element == String {
            for phrase in source where output.count < maximumContextualStringCount {
                let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let key = trimmed.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: Locale(identifier: "uk_UA")
                )
                guard seen.insert(key).inserted else { continue }
                output.append(trimmed)
            }
        }
        if includeCanonical {
            let entities = boundedVocabulary(additional: canonicalEntityVocabulary, includeCanonical: false)
            let essentialFunctions = ["QR-код", "OCR", "відскануй", "розпізнай", "відкрий", "знайди"]
            let dynamicLimit = max(0, maximumContextualStringCount - entities.count - essentialFunctions.count)
            // Fresh request-scoped values remain first, while every canonical
            // provider/app/brand keeps one display and one general spoken form.
            append(additional.prefix(dynamicLimit))
            append(entities)
            append(essentialFunctions)
            append(canonicalFunctionVocabulary)
        } else {
            append(additional)
        }
        return output
    }

    private static func preferredSpokenAlias(from aliases: Set<String>, excluding primary: String) -> [String] {
        let primaryKey = comparisonKey(primary)
        let values = aliases.filter { comparisonKey($0) != primaryKey }
        guard !values.isEmpty else { return [] }
        let preferred = values.sorted { lhs, rhs in
            let lhsCyrillic = lhs.unicodeScalars.contains { (0x0400...0x052F).contains(Int($0.value)) }
            let rhsCyrillic = rhs.unicodeScalars.contains { (0x0400...0x052F).contains(Int($0.value)) }
            if lhsCyrillic != rhsCyrillic { return lhsCyrillic }
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs < rhs
        }.first
        return preferred.map { [$0] } ?? []
    }

    private static func speechTransliterationVariants(for value: String) -> [String] {
        guard value.unicodeScalars.contains(where: { $0.isASCII && CharacterSet.letters.contains($0) }),
              let transformed = value.applyingTransform(StringTransform("Latin-Cyrillic"), reverse: false) else { return [] }
        let trimmed = transformed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, comparisonKey(trimmed) != comparisonKey(value) else { return [] }
        return [trimmed]
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert(comparisonKey($0)).inserted }
    }

    private static func comparisonKey(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "uk_UA"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func apply(to request: SFSpeechAudioBufferRecognitionRequest, recognizer: SFSpeechRecognizer? = nil) {
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.contextualStrings = contextualVocabulary
        request.requiresOnDeviceRecognition = requireOnDeviceRecognition && recognizer?.supportsOnDeviceRecognition == true
    }
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
    /// AVAudioEngine caches its I/O graph. Reusing the same graph across
    /// AVAudioSession activation, Bluetooth changes, or a previous capture can
    /// leave its input node on the old hardware format. Build 34 Crashlytics
    /// proved that exact failure at installTap. Materialize a new graph only
    /// after the session has negotiated the current route.
    private var audioEngine: AVAudioEngine?
    private var tapInstalled = false

    func configureSession() throws {
        tearDownEngine()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetoothHFP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        audioEngine = AVAudioEngine()
        let input = session.currentRoute.inputs.first?.portType.rawValue ?? "none"
        LocalVoiceDiagnosticReport.shared.record("audio_session_activated", "input=\(input) sample_rate=\(session.sampleRate)")
    }

    func installTap(_ receive: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        guard let audioEngine else { throw VoiceAudioCaptureError.invalidInputFormat }
        let input = audioEngine.inputNode
        let activeFormat = input.outputFormat(forBus: 0)
        let installationFormat = try VoiceInputTapFormatPolicy.installationFormat(for: activeFormat)
        LocalVoiceDiagnosticReport.shared.record(
            "audio_tap_installed", "sample_rate=\(activeFormat.sampleRate) channels=\(activeFormat.channelCount) format=automatic")
        input.installTap(onBus: 0, bufferSize: 1_024, format: installationFormat,
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
        guard let audioEngine else { throw VoiceAudioCaptureError.invalidInputFormat }
        audioEngine.prepare()
        try audioEngine.start()
        LocalVoiceDiagnosticReport.shared.record("audio_engine_started", "running=\(audioEngine.isRunning)")
    }

    func stop() {
        LocalVoiceDiagnosticReport.shared.record("audio_capture_stop", "running=\(audioEngine?.isRunning == true)")
        tearDownEngine()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func tearDownEngine() {
        guard let audioEngine else {
            tapInstalled = false
            return
        }
        if audioEngine.isRunning { audioEngine.stop() }
        if tapInstalled { audioEngine.inputNode.removeTap(onBus: 0) }
        tapInstalled = false
        audioEngine.reset()
        self.audioEngine = nil
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

final class VoiceRecognitionRequestSink: @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest
    private let lock = NSLock()
    private var appendedCount = 0
    private var active = true

    init(_ request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        guard active else { lock.unlock(); return }
        appendedCount += 1
        let current = appendedCount
        request.append(buffer)
        lock.unlock()
        if current == 1 || current.isMultiple(of: 100) {
            LocalVoiceDiagnosticReport.shared.record("buffer_appended", "count=\(current)")
        }
    }

    /// Audio-tap callbacks run on a realtime queue. Deactivation must happen
    /// before `endAudio`/task cancellation so a queued callback cannot append
    /// to a request whose Speech lifecycle has already ended.
    func deactivate() {
        lock.lock(); active = false; lock.unlock()
    }
}

@MainActor
final class VoiceEndOfSpeechFinalizer {
    private let delay: Duration
    private let activityPollDelay: Duration
    private let maximumActivityDeferrals: Int
    private var pending: Task<Void, Never>?

    init(
        delay: Duration = .milliseconds(1_200),
        activityPollDelay: Duration = .milliseconds(250),
        maximumActivityDeferrals: Int = 12
    ) {
        self.delay = delay
        self.activityPollDelay = activityPollDelay
        self.maximumActivityDeferrals = maximumActivityDeferrals
    }

    func receivedPartial(
        shouldDeferForVoiceActivity: @escaping @MainActor @Sendable () -> Bool = { false },
        _ finish: @escaping @MainActor @Sendable () -> Void
    ) {
        pending?.cancel()
        let delay = delay
        let activityPollDelay = activityPollDelay
        let maximumActivityDeferrals = maximumActivityDeferrals
        pending = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            var deferrals = 0
            while deferrals < maximumActivityDeferrals, shouldDeferForVoiceActivity() {
                deferrals += 1
                try? await Task.sleep(for: activityPollDelay)
                guard !Task.isCancelled else { return }
            }
            finish()
        }
    }

    func cancel() {
        pending?.cancel()
        pending = nil
    }
}

@MainActor
@Observable
final class VoiceInputController: VoiceInputControlling {
    let engineIdentifier = "apple-speech-rollback"
    private(set) var state: VoiceInputState = .idle
    private(set) var transcript = ""
    private let capture: VoiceAudioCaptureLifecycle
    private let authorization: @Sendable () async -> Bool
    private let contextualVocabulary: @Sendable () async -> [String]
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var requestSink: VoiceRecognitionRequestSink?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    // start() suspends for permissions; a newer mic tap can supersede it.
    // One token owns every resource and callback for one Speech/audio session.
    private var activeSessionID: UUID?
    private let endOfSpeechFinalizer: VoiceEndOfSpeechFinalizer
    private let speechActivity = VoiceSpeechActivityTracker()
    private var isFinalizingRecognition = false
    @ObservationIgnored private var audioEvents: AudioSessionEventMonitor?
    @ObservationIgnored private var eventHandler: (@MainActor @Sendable (VoiceInputEvent) -> Void)?
    @ObservationIgnored private var recognitionCallbackCount = 0
    @ObservationIgnored private var partialResultCount = 0
    @ObservationIgnored private var partialTranscriptHistory: [String] = []
    @ObservationIgnored private var cachedContextualVocabulary: [String] = []
    @ObservationIgnored private var vocabularyRefresh: Task<Void, Never>?
    @ObservationIgnored private var finalResultCount = 0
    @ObservationIgnored private var activeContextualVocabulary: [String] = []

    init(
        captureBackend: (any VoiceAudioCaptureBackend)? = nil,
        endOfSpeechDelay: Duration = .milliseconds(2_400),
        authorization: (@Sendable () async -> Bool)? = nil,
        contextualVocabulary: @escaping @Sendable () async -> [String] = { [] }
    ) {
        capture = VoiceAudioCaptureLifecycle(backend: captureBackend ?? AppleVoiceAudioCaptureBackend())
        self.authorization = authorization ?? Self.authorizationGranted
        self.contextualVocabulary = contextualVocabulary
        endOfSpeechFinalizer = VoiceEndOfSpeechFinalizer(delay: endOfSpeechDelay)
        audioEvents = AudioSessionEventMonitor(
            onInterruption: { [weak self] in self?.handleAudioInterruptionBegan() },
            onRouteChange: { [weak self] evidence in self?.handleAudioRouteChanged(evidence) })
        prewarmContextualVocabulary()
    }

    func start(locale: Locale = .current) async {
        stop(reason: .sessionRestart)
        let sessionID = UUID()
        activeSessionID = sessionID
        LocalVoiceDiagnosticReport.shared.reset()
        recognitionCallbackCount = 0
        partialResultCount = 0
        partialTranscriptHistory = []
        finalResultCount = 0
        isFinalizingRecognition = false
        speechActivity.reset()
        LocalVoiceDiagnosticReport.shared.record("mic_tap", "source=home")
        LocalVoiceDiagnosticReport.shared.record("start_listening_invoked")
        setState(.requestingPermission)
        guard await authorization() else {
            guard owns(sessionID) else { return }
            activeSessionID = nil
            setState(.denied)
            return
        }
        guard owns(sessionID) else {
            LocalVoiceDiagnosticReport.shared.record("stale_start_suppressed", "reason=authorization_completed")
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            activeSessionID = nil
            setState(.unavailable)
            return
        }
        LocalVoiceDiagnosticReport.shared.record("recognizer_ready", "locale=\(locale.identifier) available=\(recognizer.isAvailable)")
        self.recognizer = recognizer
        let refreshedVocabulary = await contextualVocabulary()
        guard owns(sessionID) else {
            LocalVoiceDiagnosticReport.shared.record("stale_start_suppressed", "reason=context_vocabulary_completed")
            return
        }
        if !refreshedVocabulary.isEmpty { cachedContextualVocabulary = refreshedVocabulary }
        let requestVocabulary = refreshedVocabulary.isEmpty ? cachedContextualVocabulary : refreshedVocabulary
        let request = SFSpeechAudioBufferRecognitionRequest()
        let configuration = VoiceRecognitionRequestConfiguration(additionalVocabulary: requestVocabulary)
        configuration.apply(to: request, recognizer: recognizer)
        activeContextualVocabulary = configuration.contextualVocabulary
        LocalVoiceDiagnosticReport.shared.record(
            "recognition_request_created",
            "api=sfspeechrecognizer partial_results=true punctuation=true task_hint=dictation input_count=\(requestVocabulary.count) context_count=\(configuration.contextualVocabulary.count) on_device_supported=\(recognizer.supportsOnDeviceRecognition) on_device_required=\(request.requiresOnDeviceRecognition)"
        )
        self.request = request
        let requestSink = VoiceRecognitionRequestSink(request)
        self.requestSink = requestSink
        LocalVoiceDiagnosticReport.shared.recordBoundaryPre("SPEECH_START", "locale=\(locale.identifier)")
        do {
            task = recognizer.recognitionTask(with: request, resultHandler: Self.makeRecognitionHandler(owner: self, sessionID: sessionID))
            LocalVoiceDiagnosticReport.shared.record("recognition_task_created")
            LocalVoiceDiagnosticReport.shared.beginCommandAudioRecording()
            let speechActivity = speechActivity
            try capture.start { buffer in
                speechActivity.record(buffer)
                requestSink.append(buffer)
                LocalVoiceDiagnosticReport.shared.appendCommandAudioBuffer(buffer)
            }
            guard owns(sessionID) else {
                stop(reason: .sessionRestart, ownedBy: sessionID)
                return
            }
            setState(.listening)
            prewarmContextualVocabulary()
            LocalVoiceDiagnosticReport.shared.recordBoundaryPost("SPEECH_START", "locale=\(locale.identifier) status=success")
        } catch {
            guard owns(sessionID) else { return }
            LocalVoiceDiagnosticReport.shared.record("voice_start_failed", "error_type=\(String(describing: type(of: error)))")
            stop(reason: .startFailure, ownedBy: sessionID); setState(.failed)
        }
    }

    func prewarmContextualVocabulary() {
        vocabularyRefresh?.cancel()
        let provider = contextualVocabulary
        vocabularyRefresh = Task { @MainActor [weak self] in
            let values = await provider()
            guard !Task.isCancelled else { return }
            self?.cachedContextualVocabulary = values
            LocalVoiceDiagnosticReport.shared.record(
                "speech_context_vocabulary_refreshed",
                "count=\(values.count)"
            )
        }
    }

    func stop(reason: VoiceStopReason = .externalRequest) {
        stop(reason: reason, ownedBy: nil)
    }

    private func stop(reason: VoiceStopReason, ownedBy expectedSessionID: UUID?) {
        if let expectedSessionID, !owns(expectedSessionID) {
            LocalVoiceDiagnosticReport.shared.record("stale_stop_suppressed", "reason=\(reason.rawValue)")
            return
        }
        activeSessionID = nil
        endOfSpeechFinalizer.cancel()
        isFinalizingRecognition = false
        LocalVoiceDiagnosticReport.shared.record("stop_invoked", "reason=\(reason.rawValue)")
        let hadTask = task != nil
        let hadRequest = request != nil
        requestSink?.deactivate(); requestSink = nil
        task?.cancel(); task = nil; request?.endAudio(); request = nil
        LocalVoiceDiagnosticReport.shared.record("recognition_task_cancelled", "reason=\(reason.rawValue) had_task=\(hadTask)")
        LocalVoiceDiagnosticReport.shared.record("end_audio_called", "reason=\(reason.rawValue) had_request=\(hadRequest)")
        capture.stop()
        LocalVoiceDiagnosticReport.shared.finishCommandAudioRecording(reason: reason)
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

    private func receiveRecognition(sessionID: UUID, transcript: String?, evidence: VoiceRecognitionEvidence?, isFinal: Bool, hasError: Bool, errorDomain: String, errorCode: Int) {
        guard owns(sessionID) else {
            LocalVoiceDiagnosticReport.shared.record("stale_recognition_suppressed", "final=\(isFinal) error_code=\(errorCode)")
            return
        }
        recognitionCallbackCount += 1
        if transcript != nil {
            if isFinal { finalResultCount += 1 } else { partialResultCount += 1 }
        }
        LocalVoiceDiagnosticReport.shared.record("recognition_callback", "count=\(recognitionCallbackCount) has_text=\(transcript != nil) final=\(isFinal) error_domain=\(errorDomain) error_code=\(errorCode) partial_count=\(partialResultCount) final_count=\(finalResultCount)")
        if let transcript {
            var accumulatedEvidence: VoiceRecognitionEvidence?
            if !isFinal {
                VoiceRecognitionCandidateBuilder.appendingPartial(
                    transcript,
                    to: &partialTranscriptHistory
                )
            }
            if let evidence {
                let value = evidence.withPartialTranscriptHistory(partialTranscriptHistory)
                accumulatedEvidence = value
                eventHandler?(.recognitionEvidence(value))
                let bucket = value.averageSegmentConfidence.map {
                    $0 >= 0.8 ? "high" : ($0 >= 0.5 ? "medium" : "low")
                } ?? "unavailable"
                LocalVoiceDiagnosticReport.shared.record(
                    "recognition_evidence",
                    "alternatives=\(value.alternativeTranscripts.count) segment_alternatives=\(value.segmentAlternativeCount) confidence_bucket=\(bucket)"
                )
            }
            let stabilized = isFinal
                ? accumulatedEvidence.map { VoiceTranscriptStabilizer.stabilize($0, contextualVocabulary: activeContextualVocabulary) }
                : nil
            let deliveredTranscript = stabilized?.text ?? VoiceTranscriptStabilizer.normalizedForDisplay(transcript)
            self.transcript = deliveredTranscript
            // Persist the recognizer's final evidence before handing it to the
            // semantic pipeline. If downstream parsing terminates the process,
            // Crashlytics must still contain the exact Speech boundary input.
            LocalVoiceDiagnosticReport.shared.recordSpeechTranscript(transcript, isFinal: isFinal)
            if let stabilized {
                LocalVoiceDiagnosticReport.shared.record(
                    "stabilized_transcript",
                    "length=\(stabilized.text.count) source=\(stabilized.source.rawValue)"
                )
            }
            eventHandler?(.transcript(deliveredTranscript, isFinal: isFinal))
            LocalVoiceDiagnosticReport.shared.record("transcript_delivered_to_ui", "length=\(deliveredTranscript.count) final=\(isFinal)")
            if !isFinal, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let speechActivity = speechActivity
                endOfSpeechFinalizer.receivedPartial(
                    shouldDeferForVoiceActivity: {
                        speechActivity.hasRecentVoiceActivity(within: 1.25)
                    }
                ) { [weak self] in
                    self?.finishAfterEndOfSpeech(sessionID: sessionID)
                }
            }
        }
        if hasError { stop(reason: .recognitionError, ownedBy: sessionID) }
        else if isFinal {
            LocalVoiceDiagnosticReport.shared.record("recognition_task_finished", "reason=final_result")
            stop(reason: .recognitionFinal, ownedBy: sessionID)
        }
    }

    private func finishAfterEndOfSpeech(sessionID: UUID) {
        guard owns(sessionID), state == .listening, !isFinalizingRecognition,
              let request, let task else { return }
        isFinalizingRecognition = true
        requestSink?.deactivate()
        LocalVoiceDiagnosticReport.shared.record("end_audio_called", "reason=endOfSpeech had_request=true")
        request.endAudio()
        LocalVoiceDiagnosticReport.shared.record("recognition_task_finished", "reason=endOfSpeech")
        task.finish()
        capture.stop()
        LocalVoiceDiagnosticReport.shared.finishCommandAudioRecording(reason: .recognitionFinal)
    }

    func handleAudioInterruptionBegan() {
        LocalVoiceDiagnosticReport.shared.record("audio_interruption", "state=began")
        stop(reason: .audioInterruption)
    }
    func handleAudioRouteChanged() {
        if state == .listening, !isFinalizingRecognition { stop(reason: .routeChange) }
    }

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
        owner: VoiceInputController,
        sessionID: UUID
    ) -> @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { [weak owner] result, error in
            let transcript = result?.bestTranscription.formattedString
            let evidence = result.map { result in
                let segments = result.bestTranscription.segments
                let confidenceValues = segments.map { Double($0.confidence) }.filter { $0 > 0 }
                let average = confidenceValues.isEmpty ? nil :
                    confidenceValues.reduce(0, +) / Double(confidenceValues.count)
                return VoiceRecognitionEvidence(
                    primaryTranscript: result.bestTranscription.formattedString,
                    alternativeTranscripts: Array(result.transcriptions.dropFirst()
                        .prefix(VoiceRecognitionCandidateBuilder.maximumWholeTranscriptions)
                        .map(\.formattedString)),
                    segmentAlternativeTranscripts: VoiceRecognitionCandidateBuilder.segmentAlternativeTranscripts(
                        primaryTranscript: result.bestTranscription.formattedString,
                        segments: segments
                    ),
                    segmentAlternativeCount: segments.reduce(0) { $0 + $1.alternativeSubstrings.count },
                    averageSegmentConfidence: average
                )
            }
            let isFinal = result?.isFinal == true
            let hasError = error != nil
            let nsError = error as NSError?
            let errorDomain = nsError?.domain ?? "none"
            let errorCode = nsError?.code ?? 0
            Task { @MainActor [weak owner] in
                owner?.receiveRecognition(sessionID: sessionID, transcript: transcript, evidence: evidence, isFinal: isFinal, hasError: hasError, errorDomain: errorDomain, errorCode: errorCode)
            }
        }
    }

    private func owns(_ sessionID: UUID) -> Bool { activeSessionID == sessionID }
}
