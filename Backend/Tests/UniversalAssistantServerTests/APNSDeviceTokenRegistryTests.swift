import Foundation
import Testing
@testable import UniversalAssistantServer

private func token(_ byte: UInt8) -> Data { Data(repeating: byte, count: 32) }
private func registryURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("ua-apns-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("tokens.json")
}

@Suite("APNs device token lifecycle") struct APNSDeviceTokenRegistryTests {
    @Test func multipleDevicesPersistAcrossRestart() async throws {
        let url = registryURL(), now = Date()
        let registry = try APNSDeviceTokenRegistry(fileURL: url)
        try await registry.register(userID: "user", deviceID: "iphone", token: token(1), environment: .sandbox, now: now)
        try await registry.register(userID: "user", deviceID: "ipad", token: token(2), environment: .sandbox, now: now)
        let restored = try APNSDeviceTokenRegistry(fileURL: url)
        #expect(await restored.registrations(userID: "user", environment: .sandbox).map(\.deviceID) == ["ipad", "iphone"])
    }

    @Test func refreshReplacesOldTokenWithoutDuplicatingDevice() async throws {
        let registry = try APNSDeviceTokenRegistry(fileURL: registryURL()), now = Date()
        try await registry.register(userID: "user", deviceID: "iphone", token: token(1), environment: .production, now: now)
        let refreshed = try await registry.register(userID: "user", deviceID: "iphone", token: token(2),
                                                    environment: .production, now: now.addingTimeInterval(10))
        let values = await registry.registrations(userID: "user", environment: .production)
        #expect(values.count == 1)
        #expect(values.first?.token == token(2))
        #expect(refreshed.registeredAt == now)
    }

    @Test func providerInvalidationIsEnvironmentSpecific() async throws {
        let registry = try APNSDeviceTokenRegistry(fileURL: registryURL()), now = Date()
        try await registry.register(userID: "user", deviceID: "dev", token: token(3), environment: .sandbox, now: now)
        try await registry.register(userID: "user", deviceID: "dev", token: token(3), environment: .production, now: now)
        #expect(try await registry.invalidate(token: token(3), environment: .sandbox))
        #expect(await registry.registrations(userID: "user", environment: .sandbox).isEmpty)
        #expect(await registry.registrations(userID: "user", environment: .production).count == 1)
    }

    @Test func logoutAndDeviceRemovalDeleteExactRegistrations() async throws {
        let registry = try APNSDeviceTokenRegistry(fileURL: registryURL()), now = Date()
        try await registry.register(userID: "one", deviceID: "a", token: token(4), environment: .sandbox, now: now)
        try await registry.register(userID: "one", deviceID: "b", token: token(5), environment: .sandbox, now: now)
        try await registry.register(userID: "two", deviceID: "c", token: token(6), environment: .sandbox, now: now)
        #expect(try await registry.removeDevice(userID: "one", deviceID: "a") == 1)
        #expect(try await registry.logout(userID: "one") == 1)
        #expect(await registry.registrations(userID: "two", environment: .sandbox).count == 1)
    }

    @Test func malformedTokenIsRejected() async throws {
        let registry = try APNSDeviceTokenRegistry(fileURL: registryURL())
        await #expect(throws: APNSDeviceRegistryError.invalidRegistration) {
            try await registry.register(userID: "user", deviceID: "device", token: Data([1]), environment: .sandbox)
        }
    }
}
