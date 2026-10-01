import Foundation
import Testing
@testable import UniversalAssistant

private final class VoiceSubmitCountingParser: CommandParsing, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    var submitted: [String] { lock.withLock { values } }

    func parse(_ text: String) -> StructuredCommand {
        lock.withLock { values.append(text) }
        return .init(
            originalText: text,
            normalizedText: text.lowercased(),
            language: .uk,
            intent: .help
        )
    }
}

@MainActor
@Suite("Accessibility, audio and contextual permissions")
struct AccessibilityAudioPermissionTests {
    @Test @MainActor func finalVoiceTranscriptAutoSubmitsExactlyOnceThroughCanonicalSubmit() {
        let parser = VoiceSubmitCountingParser()
        LocalVoiceDiagnosticReport.shared.detailedDiagnosticsEnabled = false
        LocalVoiceDiagnosticReport.shared.reset(requestID: UUID())
        let model = AssistantViewModel(commandEngine: parser)
        model.handleVoiceEvent(.state(.requestingPermission))
        model.handleVoiceEvent(.state(.listening))
        model.handleVoiceEvent(.transcript("відкрий календар", isFinal: false))
        #expect(model.input == "відкрий календар")
        #expect(model.isListening)

        model.handleVoiceEvent(.transcript("відкрий календар", isFinal: true))
        model.handleVoiceEvent(.transcript("відкрий календар", isFinal: true))
        #expect(parser.submitted == ["відкрий календар"])
        #expect(model.visibleVoiceTranscript == "відкрий календар")
        let report = model.voiceDiagnosticReport()
        #expect(report.contains("transcript_delivered_to_view_model"))
        #expect(report.contains("AUTO_SUBMIT_PRE"))
        #expect(report.contains("AUTO_SUBMIT_POST"))
        #expect(report.contains("transcript_delivered_to_router"))
        #expect(!report.contains("відкрий календар"))
    }

    @Test @MainActor func ios27AppleTranscriptPreservesExactTextAndSubmitsOnce() {
        let parser = VoiceSubmitCountingParser()
        let model = AssistantViewModel(commandEngine: parser)
        let appleText = "  Купити BMW сьомої серії\n"

        model.handleVoiceEvent(.state(.requestingPermission))
        model.handleVoiceEvent(.ios27AppleTranscript(appleText, isFinal: false))
        #expect(model.input == appleText)
        model.handleVoiceEvent(.ios27AppleTranscript(appleText, isFinal: true))
        model.handleVoiceEvent(.ios27AppleTranscript(appleText, isFinal: true))

        #expect(parser.submitted == [appleText])
        #expect(model.visibleVoiceTranscript == appleText)
    }

    @Test @MainActor func typedComposerWaitsForSendAndManualEditCancelsVoiceSubmit() {
        let parser = VoiceSubmitCountingParser()
        LocalVoiceDiagnosticReport.shared.detailedDiagnosticsEnabled = false
        LocalVoiceDiagnosticReport.shared.reset(requestID: UUID())
        let model = AssistantViewModel(commandEngine: parser)

        model.updateComposerTextFromUser("Покажи погоду")
        #expect(parser.submitted.isEmpty)
        model.submit()
        #expect(parser.submitted == ["Покажи погоду"])

        model.handleVoiceEvent(.state(.requestingPermission))
        model.handleVoiceEvent(.transcript("Знайди товар", isFinal: false))
        model.updateComposerTextFromUser("Знайди інший товар")
        model.handleVoiceEvent(.transcript("Знайди товар", isFinal: true))
        #expect(parser.submitted == ["Покажи погоду"])
        #expect(model.input == "Знайди інший товар")
    }

    @Test func voicePrivacyModeKeepsTypedInteractionWorking() {
        let model = AssistantViewModel()
        model.setVoiceInputEnabled(false)
        model.input = "Покажи погоду"
        model.submit()
        #expect(!model.isListening)
        #expect(model.resultState != .idle)
    }

    @Test func permissionsAreNeverRequestedAtLaunchAndRemainContextual() {
        let policy = ContextualPermissionPolicy()
        #expect(policy.decision(for: .appLaunch) == .doNotRequest)
        #expect(policy.decision(for: .proactiveFeatureEnabled) == .notifications)
        #expect(policy.decision(for: .locationTask(.nearbySearch), reducedLocationAccuracy: true) == .locationWhenInUse)
        #expect(policy.decision(for: .locationTask(.navigation), reducedLocationAccuracy: true) == .temporaryPreciseLocation)
    }

    @Test func deniedVoicePermissionOffersOneConciseSettingsRecoveryWithoutRetry() {
        let model = AssistantViewModel()
        model.applyVoiceState(.denied)
        #expect(!model.isListening)
        #expect(model.shouldOfferSettings)
        #expect(model.statusText == AppText.value("microphone_denied"))
        model.applyVoiceState(.speechDenied)
        #expect(model.shouldOfferSettings)
        #expect(model.statusText == AppText.value("speech_unavailable"))
        model.applyVoiceState(.unavailable)
        #expect(!model.shouldOfferSettings)
    }

    @Test func recorderPausesOnCallOrBluetoothRouteChange() async {
        let backend = RecorderBackendSpy()
        let controller = AudioRecorderController(backend: backend,
            directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString), permission: { true })
        await controller.start()
        controller.handleAudioInterruptionBegan()
        #expect(controller.state == .paused)
        controller.resume()
        controller.handleAudioRouteChanged()
        #expect(controller.state == .paused)
        #expect(backend.events == ["start", "pause", "resume", "pause"])
    }
}
