import Foundation

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
