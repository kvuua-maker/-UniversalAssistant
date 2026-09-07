import Foundation
#if canImport(AlarmKit)
import AlarmKit
import SwiftUI
#endif

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
    case alarmKit
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
            guard seconds > 0 else { return unavailable("invalid_timer_duration") }
            return .init(mechanism: .alarmKit, completion: .readyForUserInteraction, continuation: nil, destination: nil, reason: "public_alarmkit_timer")
        case .createAlarm(let hour, let minute):
            let validTime = (0...23).contains(hour) && (0...59).contains(minute)
            guard validTime else { return unavailable("invalid_alarm_time") }
            return .init(mechanism: .alarmKit, completion: .readyForUserInteraction, continuation: nil, destination: nil, reason: "public_alarmkit_alarm")
        }
    }

    private func isVerifiedApplicationURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), !scheme.isEmpty else { return false }
        if scheme == "https" { return url.host != nil }
        return ["maps", "comgooglemaps", "waze", "tg", "viber", "spotify"].contains(scheme)
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

#if canImport(AlarmKit)
@available(iOS 26.0, *)
private struct UniversalAssistantAlarmMetadata: AlarmMetadata { let title: String }


@available(iOS 26.0, *)
@MainActor
struct ProductionAlarmKitExecutor {
    enum ExecutionError: Error { case unsupportedOS, denied, invalidAction }

    func execute(_ action: SystemQuickAction) async throws -> String {
        guard #available(iOS 26.0, *) else { throw ExecutionError.unsupportedOS }
        let manager = AlarmManager.shared
        let authorization = manager.authorizationState == .notDetermined ? try await manager.requestAuthorization() : manager.authorizationState
        guard authorization == .authorized else { throw ExecutionError.denied }
        let stop = AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill")
        let presentation = AlarmPresentation(alert: .init(title: "UniversalAssistant", stopButton: stop))
        let attributes = AlarmAttributes<UniversalAssistantAlarmMetadata>(presentation: presentation, metadata: .init(title: "UniversalAssistant"), tintColor: .blue)
        let id = UUID()
        switch action {
        case .startTimer(let seconds) where seconds > 0:
            _ = try await manager.schedule(id: id, configuration: .timer(duration: TimeInterval(seconds), attributes: attributes))
            return "Таймер встановлено"
        case .createAlarm(let hour, let minute) where (0...23).contains(hour) && (0...59).contains(minute):
            let schedule = Alarm.Schedule.relative(.init(time: .init(hour: hour, minute: minute)))
            _ = try await manager.schedule(id: id, configuration: .alarm(schedule: schedule, attributes: attributes))
            return "Будильник встановлено"
        default: throw ExecutionError.invalidAction
        }
    }
}
#endif
