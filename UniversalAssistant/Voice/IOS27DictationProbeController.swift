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
    private let backend = IOS27DictationVoiceBackend()
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

            recordStartStage(.beforeAssetPrepare)
            if let status = await backend.assetStatus() {
                assetStatus = Self.assetStatusText(status)
            }
            recordStartStage(.afterAssetPrepare)
            startedAt = Date()
            recordStartStage(.beforeAnalyzerStart)
            try await backend.start(contextualStrings: Self.contextualStrings) { [weak self] event in self?.consume(event) }
            recordStartStage(.afterAnalyzerStart)
            recordStartStage(.running)
            isRunning = true
        } catch {
            await stopResources()
            record(error, stage: "start")
        }
    }

    func stop() async {
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

    private func consume(_ event: IOS27DictationVoiceBackend.Event) {
        let rawText: String
        let isFinal: Bool
        switch event {
        case .evidence: return // Count/text-only probe; production receives evidence separately.
        case let .partial(text): rawText = text; isFinal = false
        case let .final(text): rawText = text; isFinal = true
        case let .failure(message):
            runtimeError = message
            isRunning = false
            return
        }
        guard !rawText.isEmpty else { return }
        let now = Date()
        if firstResultLatencyMilliseconds == nil, let startedAt {
            firstResultLatencyMilliseconds = Self.milliseconds(from: startedAt, to: now)
        }

        if isFinal {
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
        await backend.stop()
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

private enum StartStage: String {
    case beforeAssetPrepare = "before_asset_prepare"
    case afterAssetPrepare = "after_asset_prepare"
    case beforeMicrophonePermissionCheck = "before_microphone_permission_check"
    case beforeMicrophonePermissionRequest = "before_microphone_permission_request"
    case afterMicrophonePermissionRequest = "after_microphone_permission_request"
    case microphonePermissionGranted = "microphone_permission_granted"
    case microphonePermissionDenied = "microphone_permission_denied"
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
