import Foundation
import Speech

enum DictationVoiceEvent: Equatable, Sendable {
    case partial(String)
    case final(String)
    case evidence(VoiceRecognitionEvidence)
    case failure(String)
}

enum DictationVoiceBackendError: LocalizedError {
    case unsupportedLocale, microphoneUnavailable, microphonePermissionDenied
    case assetsUnsupported, assetsNotInstalled, captureSessionDidNotStart

    var errorDescription: String? {
        switch self {
        case .unsupportedLocale: "DictationTranscriber does not support uk-UA on this device."
        case .microphoneUnavailable: "No microphone capture device is available."
        case .microphonePermissionDenied: "Microphone permission was denied."
        case .assetsUnsupported: "Required DictationTranscriber assets are unsupported."
        case .assetsNotInstalled: "Required DictationTranscriber assets are not installed."
        case .captureSessionDidNotStart: "The microphone capture session did not start."
        }
    }
}

@MainActor
protocol DictationVoiceSession: AnyObject {
    func start(contextualStrings: [String], onEvent: @escaping @MainActor @Sendable (DictationVoiceEvent) -> Void) async throws
    func finish() async throws
    func stop() async
}

/// Public Speech attributes only. No inferred confidence or invented spelling alternatives.
/// Kept separate from the SDK27 capture provider so its conversion is also testable on SDK26.
@available(iOS 26.0, *)
enum DictationRecognitionEvidence {
    static func make(text: AttributedString, alternatives: [AttributedString]) -> VoiceRecognitionEvidence {
        let primary = String(text.characters)
        var seen: Set<String> = [primary]
        let values = alternatives.map { String($0.characters) }.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && seen.insert($0).inserted
        }
        let confidence = text.runs.compactMap { run -> Double? in
            guard let value = run[AttributeScopes.SpeechAttributes.ConfidenceAttribute.self],
                  value.isFinite, (0...1).contains(value) else { return nil }
            return value
        }
        return .init(primaryTranscript: primary, alternativeTranscripts: Array(values.prefix(8)),
                     segmentAlternativeCount: 0,
                     averageSegmentConfidence: confidence.isEmpty ? nil : confidence.reduce(0, +) / Double(confidence.count))
    }
}
