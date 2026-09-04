import AVFoundation
import Foundation

struct AudioRouteChangeEvidence: Equatable, Sendable {
    let reasonRawValue: UInt
    let reasonName: String
    let previousInputs: [String]
    let previousOutputs: [String]
    let currentInputs: [String]
    let currentOutputs: [String]
    let inputAvailable: Bool

    static func capture(notification: Notification, session: AVAudioSession = .sharedInstance()) -> Self {
        let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
        let reason = AVAudioSession.RouteChangeReason(rawValue: raw) ?? .unknown
        let previous = notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
        return .init(reasonRawValue: raw, reasonName: reason.diagnosticName,
                     previousInputs: previous?.inputs.map(\.diagnosticDescription) ?? [],
                     previousOutputs: previous?.outputs.map(\.diagnosticDescription) ?? [],
                     currentInputs: session.currentRoute.inputs.map(\.diagnosticDescription),
                     currentOutputs: session.currentRoute.outputs.map(\.diagnosticDescription),
                     inputAvailable: session.isInputAvailable)
    }

    var diagnosticDescription: String {
        "reason=\(reasonName)(\(reasonRawValue)) previous_inputs=\(previousInputs) previous_outputs=\(previousOutputs) current_inputs=\(currentInputs) current_outputs=\(currentOutputs) input_available=\(inputAvailable)"
    }

    var requiresVoiceCaptureStop: Bool {
        guard inputAvailable, !currentInputs.isEmpty else { return true }
        switch AVAudioSession.RouteChangeReason(rawValue: reasonRawValue) ?? .unknown {
        case .newDeviceAvailable, .categoryChange, .override, .wakeFromSleep,
             .routeConfigurationChange:
            return false
        case .oldDeviceUnavailable, .noSuitableRouteForCategory, .unknown:
            return true
        @unknown default:
            return true
        }
    }
}

private extension AVAudioSession.RouteChangeReason {
    var diagnosticName: String {
        switch self {
        case .unknown: "unknown"
        case .newDeviceAvailable: "newDeviceAvailable"
        case .oldDeviceUnavailable: "oldDeviceUnavailable"
        case .categoryChange: "categoryChange"
        case .override: "override"
        case .wakeFromSleep: "wakeFromSleep"
        case .noSuitableRouteForCategory: "noSuitableRouteForCategory"
        case .routeConfigurationChange: "routeConfigurationChange"
        @unknown default: "future(\(rawValue))"
        }
    }
}

private extension AVAudioSessionPortDescription {
    var diagnosticDescription: String { "\(portType.rawValue):\(portName)" }
}

@MainActor
final class AudioSessionEventMonitor {
    nonisolated(unsafe) private var tokens: [NSObjectProtocol] = []

    init(onInterruption: @escaping @MainActor () -> Void,
         onRouteChange: @escaping @MainActor (AudioRouteChangeEvidence) -> Void) {
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
                                         object: nil, queue: .main) { notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            Task { @MainActor in onInterruption() }
        })
        tokens.append(center.addObserver(forName: AVAudioSession.routeChangeNotification,
                                         object: nil, queue: .main) { notification in
            let evidence = AudioRouteChangeEvidence.capture(notification: notification)
            Task { @MainActor in onRouteChange(evidence) }
        })
    }

    deinit { for token in tokens { NotificationCenter.default.removeObserver(token) } }
}
