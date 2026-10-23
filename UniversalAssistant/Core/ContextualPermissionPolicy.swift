import Foundation
import UIKit
import UserNotifications

enum PermissionTrigger: Equatable, Sendable { case appLaunch, explicitVoiceAction, proactiveFeatureEnabled, locationTask(LocationPurpose) }
enum PermissionRequestDecision: Equatable, Sendable { case doNotRequest, microphone, notifications, locationWhenInUse, temporaryPreciseLocation }

struct ContextualPermissionPolicy: Sendable {
    func decision(for trigger: PermissionTrigger, reducedLocationAccuracy: Bool = false) -> PermissionRequestDecision {
        switch trigger {
        case .appLaunch: .doNotRequest
        case .explicitVoiceAction: .microphone
        case .proactiveFeatureEnabled: .notifications
        case let .locationTask(purpose):
            if reducedLocationAccuracy && (purpose == .navigation || purpose == .emergency) { .temporaryPreciseLocation }
            else { .locationWhenInUse }
        }
    }
}

enum ProactiveNotificationEnableResult: Equatable, Sendable {
    case enabled
    case denied
    case failed
}

@MainActor
enum ProductionNotificationRegistration {
    static func enable() async -> ProactiveNotificationEnableResult {
        guard ContextualPermissionPolicy().decision(for: .proactiveFeatureEnabled) == .notifications else { return .failed }
        do {
            let center = UNUserNotificationCenter.current()
            // UNNotificationSettings is not Sendable; only the status crosses.
            let status: UNAuthorizationStatus = await withCheckedContinuation { continuation in
                center.getNotificationSettings { continuation.resume(returning: $0.authorizationStatus) }
            }
            let granted: Bool
            switch status {
            case .authorized, .provisional, .ephemeral: granted = true
            case .denied: granted = false
            case .notDetermined: granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            @unknown default: granted = false
            }
            guard granted else { return .denied }
            UIApplication.shared.registerForRemoteNotifications()
            return .enabled
        } catch {
            return .failed
        }
    }
}
