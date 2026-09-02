import Foundation

public enum APNSEnvironment: String, Codable, Sendable { case sandbox, production }

public struct APNSDeviceRegistration: Codable, Equatable, Sendable {
    public let userID: String
    public let deviceID: String
    public let token: Data
    public let environment: APNSEnvironment
    public let registeredAt: Date
    public let updatedAt: Date

    public init(userID: String, deviceID: String, token: Data, environment: APNSEnvironment,
                registeredAt: Date, updatedAt: Date) {
        self.userID = userID
        self.deviceID = deviceID
        self.token = token
        self.environment = environment
        self.registeredAt = registeredAt
        self.updatedAt = updatedAt
    }
}

public enum APNSDeviceRegistryError: Error, Equatable, Sendable {
    case invalidRegistration
}

public actor APNSDeviceTokenRegistry {
    private struct Snapshot: Codable { var registrations: [APNSDeviceRegistration] = [] }
    private let fileURL: URL
    private var snapshot: Snapshot

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: fileURL))
        } else {
            snapshot = Snapshot()
        }
    }

    @discardableResult
    public func register(userID: String, deviceID: String, token: Data,
                         environment: APNSEnvironment, now: Date = .now) throws -> APNSDeviceRegistration {
        guard validIdentifier(userID), validIdentifier(deviceID), token.count == 32 else {
            throw APNSDeviceRegistryError.invalidRegistration
        }
        let existing = snapshot.registrations.first {
            $0.userID == userID && $0.deviceID == deviceID && $0.environment == environment
        }
        // A token identifies one app/device/environment tuple. Remove stale ownership and token rotations.
        snapshot.registrations.removeAll {
            ($0.deviceID == deviceID && $0.environment == environment) ||
            ($0.token == token && $0.environment == environment)
        }
        let registration = APNSDeviceRegistration(
            userID: userID, deviceID: deviceID, token: token, environment: environment,
            registeredAt: existing?.registeredAt ?? now, updatedAt: now
        )
        snapshot.registrations.append(registration)
        try persist()
        return registration
    }

    public func registrations(userID: String, environment: APNSEnvironment) -> [APNSDeviceRegistration] {
        snapshot.registrations.filter { $0.userID == userID && $0.environment == environment }
            .sorted { $0.deviceID < $1.deviceID }
    }

    @discardableResult
    public func invalidate(token: Data, environment: APNSEnvironment) throws -> Bool {
        let before = snapshot.registrations.count
        snapshot.registrations.removeAll { $0.token == token && $0.environment == environment }
        try persist()
        return before != snapshot.registrations.count
    }

    @discardableResult
    public func removeDevice(userID: String, deviceID: String) throws -> Int {
        let before = snapshot.registrations.count
        snapshot.registrations.removeAll { $0.userID == userID && $0.deviceID == deviceID }
        try persist()
        return before - snapshot.registrations.count
    }

    @discardableResult
    public func logout(userID: String) throws -> Int {
        let before = snapshot.registrations.count
        snapshot.registrations.removeAll { $0.userID == userID }
        try persist()
        return before - snapshot.registrations.count
    }

    private func validIdentifier(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 128
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
