import AVFoundation
import Foundation

@MainActor
final class AudioSessionEventMonitor {
    nonisolated(unsafe) private var tokens: [NSObjectProtocol] = []

    init(onInterruption: @escaping @MainActor () -> Void,
         onRouteChange: @escaping @MainActor () -> Void) {
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
                                         object: nil, queue: .main) { notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            Task { @MainActor in onInterruption() }
        })
        tokens.append(center.addObserver(forName: AVAudioSession.routeChangeNotification,
                                         object: nil, queue: .main) { _ in
            Task { @MainActor in onRouteChange() }
        })
    }

    deinit { for token in tokens { NotificationCenter.default.removeObserver(token) } }
}
