#if IOS27_SPEECH_PROBE
import AVFoundation
import Foundation
import Speech

@available(iOS 27.0, *)
@MainActor
final class IOS27DictationVoiceBackend {
    enum Event: Equatable, Sendable {
        case partial(String)
        case final(String)
        case failure(String)
    }

    enum BackendError: LocalizedError {
        case unsupportedLocale
        case microphoneUnavailable
        case microphonePermissionDenied
        case assetsUnsupported
        case assetsNotInstalled
        case captureSessionDidNotStart

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

    static let requestedLocale = Locale(identifier: "uk-UA")
    private static var preparedLocaleIdentifiers = Set<String>()

    private let captureWorker = IOS27DictationCaptureWorker()
    private var analyzer: SpeechAnalyzer?
    private var captureProvider: CaptureInputSequenceProvider?
    private var resultsTask: Task<Void, Never>?
    private var sessionID: UUID?
    private var emittedFinal = false

    func resolvedLocale() async -> Locale? {
        await DictationTranscriber.supportedLocale(equivalentTo: Self.requestedLocale)
    }

    func assetStatus() async -> AssetInventory.Status? {
        guard let locale = await resolvedLocale() else { return nil }
        let transcriber = DictationTranscriber(locale: locale, preset: .progressiveShortDictation)
        return await AssetInventory.status(forModules: [transcriber])
    }

    func start(
        onEvent: @escaping @MainActor @Sendable (Event) -> Void
    ) async throws {
        await stop()
        let newSessionID = UUID()
        sessionID = newSessionID
        emittedFinal = false

        guard let locale = await resolvedLocale() else {
            sessionID = nil
            throw BackendError.unsupportedLocale
        }
        let transcriber = DictationTranscriber(locale: locale, preset: .progressiveShortDictation)
        try await prepareAssets(for: transcriber, locale: locale)
        try await requireMicrophonePermission()

        let providerHandle = try await captureWorker.makeProvider(
            compatibleWith: transcriber
        )
        let provider = providerHandle.provider
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        captureProvider = provider

        resultsTask = Task { @MainActor [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self, self.sessionID == newSessionID, !Task.isCancelled else { return }
                    let text = String(result.text.characters)
                    guard !text.isEmpty else { continue }
                    if result.isFinal {
                        guard !self.emittedFinal else { continue }
                        self.emittedFinal = true
                        onEvent(.final(text))
                        Task { @MainActor [weak self] in await self?.stop(sessionID: newSessionID) }
                    } else if !self.emittedFinal {
                        onEvent(.partial(text))
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.sessionID == newSessionID else { return }
                onEvent(.failure(String(describing: error)))
                await self.stop(sessionID: newSessionID)
            }
        }

        do {
            try await analyzer.start(inputSequence: provider.analyzerInputs)
            guard sessionID == newSessionID else { throw CancellationError() }
            guard await captureWorker.startCapture() else {
                throw BackendError.captureSessionDidNotStart
            }
        } catch {
            await stop(sessionID: newSessionID)
            throw error
        }
    }

    func stop() async {
        guard let sessionID else { return }
        await stop(sessionID: sessionID)
    }

    func finish() async throws {
        guard sessionID != nil, let analyzer else { return }
        await captureWorker.stopCapture()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
    }

    private func stop(sessionID expectedSessionID: UUID) async {
        guard sessionID == expectedSessionID else { return }
        sessionID = nil
        await captureWorker.stopAndReset()
        if let analyzer { await analyzer.cancelAndFinishNow() }
        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
        captureProvider = nil
    }

    private func prepareAssets(for transcriber: DictationTranscriber, locale: Locale) async throws {
        let localeID = locale.identifier.lowercased()
        if Self.preparedLocaleIdentifiers.contains(localeID),
           await AssetInventory.status(forModules: [transcriber]) == .installed {
            return
        }
        let modules: [any SpeechModule] = [transcriber]
        switch await AssetInventory.status(forModules: modules) {
        case .installed:
            Self.preparedLocaleIdentifiers.insert(localeID)
        case .unsupported:
            throw BackendError.assetsUnsupported
        case .supported, .downloading:
            if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                try await request.downloadAndInstall()
            }
            guard await AssetInventory.status(forModules: modules) == .installed else {
                throw BackendError.assetsNotInstalled
            }
            Self.preparedLocaleIdentifiers.insert(localeID)
        @unknown default:
            throw BackendError.assetsNotInstalled
        }
    }

    private func requireMicrophonePermission() async throws {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return
        case .denied:
            throw BackendError.microphonePermissionDenied
        case .undetermined:
            guard await AVAudioApplication.requestRecordPermission() else {
                throw BackendError.microphonePermissionDenied
            }
        @unknown default:
            throw BackendError.microphonePermissionDenied
        }
    }
}

@available(iOS 27.0, *)
private actor IOS27DictationCaptureWorker {
    private var captureSession: AVCaptureSession?

    func makeProvider(
        compatibleWith transcriber: DictationTranscriber
    ) async throws -> IOS27DictationCaptureProviderHandle {
        guard let microphone = AVCaptureDevice.default(for: .audio) else {
            throw IOS27DictationVoiceBackend.BackendError.microphoneUnavailable
        }
        let provider = try await CaptureInputSequenceProvider.providerWithSession(
            from: microphone,
            compatibleWith: [transcriber],
            priority: .userInitiated
        )
        captureSession = provider.captureSession
        return IOS27DictationCaptureProviderHandle(provider: provider)
    }

    func startCapture() -> Bool {
        guard let captureSession else { return false }
        captureSession.startRunning()
        return captureSession.isRunning
    }

    func stopCapture() {
        if let captureSession, captureSession.isRunning { captureSession.stopRunning() }
    }

    func stopAndReset() {
        if let captureSession, captureSession.isRunning { captureSession.stopRunning() }
        captureSession = nil
    }
}

@available(iOS 27.0, *)
private final class IOS27DictationCaptureProviderHandle: @unchecked Sendable {
    let provider: CaptureInputSequenceProvider
    init(provider: CaptureInputSequenceProvider) { self.provider = provider }
}
#endif
