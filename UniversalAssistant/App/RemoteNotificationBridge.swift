import Foundation
import UIKit

/// Receives the APNs device token. Before this bridge existed the app declared
/// the `aps-environment` entitlement and shipped `ProductionNotificationRegistration`
/// but nothing ever consumed the token, so remote notifications could never be
/// addressed to a device.
///
/// The token is device-scoped, not personal, and is stored with the same
/// protection class as other assistant-owned records.
actor DeviceTokenStore {
    static let shared = DeviceTokenStore()
    private let store: LocalStore
    private let filename: String

    init(store: LocalStore = .shared, filename: String = "apns-device-token.json") {
        self.store = store
        self.filename = filename
    }

    struct Record: Codable, Equatable, Sendable {
        let token: String
        let environment: String
        let updatedAt: Date
    }

    func save(token: String, environment: String) async throws {
        guard !token.isEmpty else { throw DeviceTokenError.invalidToken }
        try await store.save(
            Record(token: token, environment: environment, updatedAt: Date()), as: filename)
    }

    func load() async throws -> Record? { try await store.load(Record.self, from: filename) }

    func currentToken() async -> String? {
        (try? await store.load(Record.self, from: filename))??.token
    }
}

enum DeviceTokenError: Error, Equatable { case invalidToken }

@MainActor
final class RemoteNotificationBridge: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let shared = RemoteNotificationBridge()

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        #if DEBUG
            let environment = "development"
        #else
            let environment = "production"
        #endif
        Task { try? await DeviceTokenStore.shared.save(token: hex, environment: environment) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Registration failure is a truthful, non-blocking state: local
        // features keep working and the next launch retries.
        LocalVoiceDiagnosticReport.shared.record(
            "apns_registration_failed", "error_domain=\((error as NSError).domain)")
    }

    /// Requests the token only when the user already granted notification
    /// permission; never prompts from here.
    static func registerIfAuthorized() async {
        // UNNotificationSettings is not Sendable; only the status enum crosses
        // the concurrency boundary.
        let status: UNAuthorizationStatus = await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
        switch status {
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
        case .denied, .notDetermined:
            return
        @unknown default:
            return
        }
    }
}
