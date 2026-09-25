#if IOS27_SPEECH_PROBE
import AVFoundation
import Combine
import Darwin
import Foundation
import Speech
import UIKit

@available(iOS 27.0, *)
@MainActor
final class IOS27DictationProbeController: ObservableObject {
    static let requestedLocaleIdentifier = "uk-UA"
    static let contextualStrings = [
        "Viber", "вайбер", "Telegram", "телеграм", "WhatsApp",
        "Spotify", "Київ", "Львів", "QR", "PDF"
    ]

    @Published private(set) var resolvedLocaleIdentifier = "NOT CHECKED"
    @Published private(set) var requestedLocaleSupported = false
    @Published private(set) var requestedLocaleInstalled = false
    @Published private(set) var assetStatus = "NOT CHECKED"
    @Published private(set) var assetInstallation = "NOT REQUIRED"
    @Published private(set) var liveTranscript = ""
    @Published private(set) var finalTranscript = ""
    @Published private(set) var firstResultLatencyMilliseconds: Int?
    @Published private(set) var finalResultLatencyMilliseconds: Int?
    @Published private(set) var runtimeError: String?
    @Published private(set) var lastStartStage: String
    @Published private(set) var isPreparing = false
    @Published private(set) var isRunning = false

    let iOSVersion = UIDevice.current.systemVersion
    let deviceModel = IOS27DictationProbeController.hardwareModelIdentifier()

    private let requestedLocale = Locale(identifier: requestedLocaleIdentifier)
    private let captureWorker = ProbeCaptureWorker()
    private var analyzer: SpeechAnalyzer?
    private var captureProvider: CaptureInputSequenceProvider?
    private var resultsTask: Task<Void, Never>?
    private var startedAt: Date?
    private var finalChunks: [String] = []

    init() {
        lastStartStage = UserDefaults.standard.string(forKey: Self.lastStartStageKey) ?? "NONE"
    }

    func refreshCapabilities() async {
        guard !isRunning, !isPreparing else { return }
        isPreparing = true
        runtimeError = nil
        defer { isPreparing = false }

        let supported = await DictationTranscriber.supportedLocales
        let installed = await DictationTranscriber.installedLocales
        requestedLocaleSupported = supported.contains { Self.sameLocale($0, requestedLocale) }
        requestedLocaleInstalled = installed.contains { Self.sameLocale($0, requestedLocale) }

        guard let resolved = await DictationTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            resolvedLocaleIdentifier = "UNSUPPORTED"
            assetStatus = "UNSUPPORTED"
            return
        }

        resolvedLocaleIdentifier = resolved.identifier
        let transcriber = DictationTranscriber(locale: resolved, preset: .progressiveShortDictation)
        assetStatus = Self.assetStatusText(await AssetInventory.status(forModules: [transcriber]))
    }

    func start() async {
        guard !isRunning, !isPreparing else { return }
        isPreparing = true
        resetSessionEvidence()
        defer { isPreparing = false }

        do {
            let supported = await DictationTranscriber.supportedLocales
            let installed = await DictationTranscriber.installedLocales
            requestedLocaleSupported = supported.contains { Self.sameLocale($0, requestedLocale) }
            requestedLocaleInstalled = installed.contains { Self.sameLocale($0, requestedLocale) }

            guard let resolved = await DictationTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
                resolvedLocaleIdentifier = "UNSUPPORTED"
                assetStatus = "UNSUPPORTED"
                throw ProbeError.unsupportedUkrainianLocale
            }
            resolvedLocaleIdentifier = resolved.identifier

            let transcriber = DictationTranscriber(locale: resolved, preset: .progressiveShortDictation)
            recordStartStage(.beforeAssetPrepare)
            try await prepareAssets(for: transcriber)
            recordStartStage(.afterAssetPrepare)
            recordStartStage(.beforePermissions)
            try await requirePermissions()
            recordStartStage(.afterPermissions)
            recordStartStage(.beforeCaptureProvider)
            let providerHandle = try await captureWorker.makeProvider(compatibleWith: transcriber)
            let provider = providerHandle.provider
            recordStartStage(.afterCaptureProvider)
            let context = AnalysisContext()
            context.contextualStrings[.general] = Self.contextualStrings

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            try await analyzer.setContext(context)

            self.analyzer = analyzer
            captureProvider = provider
            startedAt = Date()
            resultsTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        guard !Task.isCancelled else { return }
                        self?.consume(result)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    self?.record(error, stage: "results")
                }
            }

            recordStartStage(.beforeAnalyzerStart)
            try await analyzer.start(inputSequence: provider.analyzerInputs)
            recordStartStage(.afterAnalyzerStart)
            recordStartStage(.beforeCaptureStart)
            guard await captureWorker.startCapture() else {
                throw ProbeError.captureSessionDidNotStart
            }
            recordStartStage(.running)
            isRunning = true
        } catch {
            await stopResources()
            record(error, stage: "start")
        }
    }

    func stop() async {
        guard isRunning || analyzer != nil || captureProvider != nil else { return }
        await stopResources()
    }

    var reportText: String {
        [
            "iOS version: \(iOSVersion)",
            "Device model: \(deviceModel)",
            "Requested locale: \(Self.requestedLocaleIdentifier)",
            "Resolved supported locale: \(resolvedLocaleIdentifier)",
            "uk-UA in supportedLocales: \(Self.yesNo(requestedLocaleSupported))",
            "uk-UA in installedLocales: \(Self.yesNo(requestedLocaleInstalled))",
            "Speech asset status: \(assetStatus)",
            "Asset download/install: \(assetInstallation)",
            "Live transcript: \(liveTranscript)",
            "Final transcript: \(finalTranscript)",
            "First-result latency ms: \(firstResultLatencyMilliseconds.map(String.init) ?? "NONE")",
            "Final-result latency ms: \(finalResultLatencyMilliseconds.map(String.init) ?? "NONE")",
            "Last start stage: \(lastStartStage)",
            "Runtime error: \(runtimeError ?? "NONE")"
        ].joined(separator: "\n")
    }

    private func prepareAssets(for transcriber: DictationTranscriber) async throws {
        let modules: [any SpeechModule] = [transcriber]
        let before = await AssetInventory.status(forModules: modules)
        assetStatus = Self.assetStatusText(before)

        switch before {
        case .installed:
            assetInstallation = "NOT REQUIRED"
        case .unsupported:
            assetInstallation = "FAIL: UNSUPPORTED"
            throw ProbeError.assetsUnsupported
        case .supported, .downloading:
            guard let request = try await AssetInventory.assetInstallationRequest(supporting: modules) else {
                let status = await AssetInventory.status(forModules: modules)
                assetStatus = Self.assetStatusText(status)
                guard status == .installed else {
                    assetInstallation = "FAIL: \(assetStatus)"
                    throw ProbeError.assetsNotInstalled(assetStatus)
                }
                assetInstallation = "PASS"
                return
            }
            do {
                try await request.downloadAndInstall()
            } catch {
                assetInstallation = "FAIL: \(Self.errorText(error))"
                throw error
            }
            let after = await AssetInventory.status(forModules: modules)
            assetStatus = Self.assetStatusText(after)
            guard after == .installed else {
                assetInstallation = "FAIL: \(assetStatus)"
                throw ProbeError.assetsNotInstalled(assetStatus)
            }
            assetInstallation = "PASS"
            requestedLocaleInstalled = (await DictationTranscriber.installedLocales).contains {
                Self.sameLocale($0, requestedLocale)
            }
        @unknown default:
            assetInstallation = "FAIL: UNKNOWN STATUS"
            throw ProbeError.assetsNotInstalled("UNKNOWN STATUS")
        }
    }

    private func requirePermissions() async throws {
        let microphone = await AVCaptureDevice.requestAccess(for: .audio)
        guard microphone else { throw ProbeError.microphonePermissionDenied }

        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speech == .authorized else {
            throw ProbeError.speechPermissionDenied(String(describing: speech))
        }
    }

    private func consume(_ result: DictationTranscriber.Result) {
        let rawText = String(result.text.characters)
        guard !rawText.isEmpty else { return }
        let now = Date()
        if firstResultLatencyMilliseconds == nil, let startedAt {
            firstResultLatencyMilliseconds = Self.milliseconds(from: startedAt, to: now)
        }

        if result.isFinal {
            finalChunks.append(rawText)
            finalTranscript = finalChunks.joined(separator: " ")
            liveTranscript = finalTranscript
            if finalResultLatencyMilliseconds == nil, let startedAt {
                finalResultLatencyMilliseconds = Self.milliseconds(from: startedAt, to: now)
            }
        } else {
            liveTranscript = (finalChunks + [rawText]).joined(separator: " ")
        }
    }

    private func stopResources() async {
        await captureWorker.stopAndReset()
        if let analyzer {
            await analyzer.cancelAndFinishNow()
        }
        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
        captureProvider = nil
        isRunning = false
    }

    private func resetSessionEvidence() {
        runtimeError = nil
        liveTranscript = ""
        finalTranscript = ""
        firstResultLatencyMilliseconds = nil
        finalResultLatencyMilliseconds = nil
        finalChunks = []
        startedAt = nil
        assetInstallation = "NOT REQUIRED"
    }

    private func record(_ error: Error, stage: String) {
        runtimeError = "stage=\(stage) \(Self.errorText(error))"
    }

    private func recordStartStage(_ stage: StartStage) {
        lastStartStage = stage.rawValue
        UserDefaults.standard.set(stage.rawValue, forKey: Self.lastStartStageKey)
        UserDefaults.standard.synchronize()
    }

    private static func sameLocale(_ lhs: Locale, _ rhs: Locale) -> Bool {
        lhs.identifier.replacingOccurrences(of: "_", with: "-").lowercased()
            == rhs.identifier.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    private static func assetStatusText(_ status: AssetInventory.Status) -> String {
        switch status {
        case .unsupported: "UNSUPPORTED"
        case .supported: "SUPPORTED, NOT INSTALLED"
        case .downloading: "DOWNLOADING"
        case .installed: "INSTALLED"
        @unknown default: "UNKNOWN"
        }
    }

    private static func errorText(_ error: Error) -> String {
        let nsError = error as NSError
        return "domain=\(nsError.domain) code=\(nsError.code) description=\(nsError.localizedDescription)"
    }

    private static func milliseconds(from start: Date, to end: Date) -> Int {
        max(0, Int((end.timeIntervalSince(start) * 1_000).rounded()))
    }

    private static func yesNo(_ value: Bool) -> String { value ? "YES" : "NO" }

    private static let lastStartStageKey = "ios27DictationProbe.lastStartStage"

    private static func hardwareModelIdentifier() -> String {
        var size = 0
        guard sysctlbyname("hw.machine", nil, &size, nil, 0) == 0, size > 0 else {
            return UIDevice.current.model
        }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.machine", &bytes, &size, nil, 0) == 0 else {
            return UIDevice.current.model
        }
        return String(cString: bytes)
    }
}

@available(iOS 27.0, *)
private actor ProbeCaptureWorker {
    private var captureSession: AVCaptureSession?

    func makeProvider(
        compatibleWith transcriber: DictationTranscriber
    ) async throws -> ProbeCaptureProviderHandle {
        guard let microphone = AVCaptureDevice.default(for: .audio) else {
            throw ProbeError.microphoneUnavailable
        }
        let provider = try await CaptureInputSequenceProvider.providerWithSession(
            from: microphone,
            compatibleWith: [transcriber],
            priority: .userInitiated
        )
        captureSession = provider.captureSession
        return ProbeCaptureProviderHandle(provider: provider)
    }

    func startCapture() -> Bool {
        guard let captureSession else { return false }
        captureSession.startRunning()
        return captureSession.isRunning
    }

    func stopAndReset() {
        if let captureSession, captureSession.isRunning {
            captureSession.stopRunning()
        }
        captureSession = nil
    }
}

@available(iOS 27.0, *)
private final class ProbeCaptureProviderHandle: @unchecked Sendable {
    let provider: CaptureInputSequenceProvider

    init(provider: CaptureInputSequenceProvider) {
        self.provider = provider
    }
}

private enum StartStage: String {
    case beforeAssetPrepare = "before_asset_prepare"
    case afterAssetPrepare = "after_asset_prepare"
    case beforePermissions = "before_permissions"
    case afterPermissions = "after_permissions"
    case beforeCaptureProvider = "before_capture_provider"
    case afterCaptureProvider = "after_capture_provider"
    case beforeAnalyzerStart = "before_analyzer_start"
    case afterAnalyzerStart = "after_analyzer_start"
    case beforeCaptureStart = "before_capture_start"
    case running
}

@available(iOS 27.0, *)
private enum ProbeError: LocalizedError {
    case unsupportedUkrainianLocale
    case microphoneUnavailable
    case microphonePermissionDenied
    case speechPermissionDenied(String)
    case assetsUnsupported
    case assetsNotInstalled(String)
    case captureSessionDidNotStart

    var errorDescription: String? {
        switch self {
        case .unsupportedUkrainianLocale:
            "DictationTranscriber does not support uk-UA on this device."
        case .microphoneUnavailable:
            "No microphone capture device is available."
        case .microphonePermissionDenied:
            "Microphone permission was denied."
        case let .speechPermissionDenied(status):
            "Speech recognition permission is not authorized: \(status)."
        case .assetsUnsupported:
            "Required DictationTranscriber assets are unsupported."
        case let .assetsNotInstalled(status):
            "Required DictationTranscriber assets are not installed: \(status)."
        case .captureSessionDidNotStart:
            "The microphone capture session did not start."
        }
    }
}
#endif
