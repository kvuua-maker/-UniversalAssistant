import Foundation

enum SystemQuickAction: Equatable, Sendable {
    case takePhoto
    case openFiles
    case openApp(verifiedURL: URL)
    case startTimer(seconds: Int)
    case createAlarm(hour: Int, minute: Int)
    case captureThen(QuickActionContinuation)
}

enum QuickActionContinuation: String, Equatable, Sendable {
    case shareWithContact
    case translateSelection
    case identifyProduct
}

enum SystemQuickActionMechanism: String, Equatable, Sendable {
    case avFoundationCapture
    case documentPicker
    case verifiedApplicationURL
    case unavailable
}

enum QuickActionCompletion: String, Equatable, Sendable {
    case readyForUserInteraction
    case requiresCapturedAsset
    case unsupported
}

struct SystemQuickActionPlan: Equatable, Sendable {
    let mechanism: SystemQuickActionMechanism
    let completion: QuickActionCompletion
    let continuation: QuickActionContinuation?
    let destination: URL?
    let reason: String
}

struct SystemQuickActionPlanner: Sendable {
    func plan(_ action: SystemQuickAction) -> SystemQuickActionPlan {
        switch action {
        case .takePhoto:
            return .init(
                mechanism: .avFoundationCapture,
                completion: .readyForUserInteraction,
                continuation: nil,
                destination: nil,
                reason: "public_camera_capture_requires_user_visible_session"
            )
        case .captureThen(let continuation):
            return .init(
                mechanism: .avFoundationCapture,
                completion: .requiresCapturedAsset,
                continuation: continuation,
                destination: nil,
                reason: "capture_first_then_continue_with_authorized_asset"
            )
        case .openFiles:
            return .init(
                mechanism: .documentPicker,
                completion: .readyForUserInteraction,
                continuation: nil,
                destination: nil,
                reason: "public_document_picker"
            )
        case .openApp(let url):
            guard isVerifiedApplicationURL(url) else {
                return unavailable("unverified_or_unsafe_application_url")
            }
            return .init(
                mechanism: .verifiedApplicationURL,
                completion: .readyForUserInteraction,
                continuation: nil,
                destination: url,
                reason: "verified_application_destination"
            )
        case .startTimer(let seconds):
            return unavailable(seconds > 0 ? "no_public_ios_timer_creation_api" : "invalid_timer_duration")
        case .createAlarm(let hour, let minute):
            let validTime = (0...23).contains(hour) && (0...59).contains(minute)
            return unavailable(validTime ? "no_public_ios_alarm_creation_api" : "invalid_alarm_time")
        }
    }

    private func isVerifiedApplicationURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), !scheme.isEmpty else { return false }
        if scheme == "https" { return url.host != nil }
        return ["maps", "comgooglemaps", "waze", "tg", "viber"].contains(scheme)
    }

    private func unavailable(_ reason: String) -> SystemQuickActionPlan {
        .init(
            mechanism: .unavailable,
            completion: .unsupported,
            continuation: nil,
            destination: nil,
            reason: reason
        )
    }
}
