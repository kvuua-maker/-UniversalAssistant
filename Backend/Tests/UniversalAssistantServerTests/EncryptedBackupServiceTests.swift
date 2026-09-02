import Foundation
import Testing
@testable import UniversalAssistantServer

@Suite("Encrypted backup and disaster recovery")
struct EncryptedBackupServiceTests {
    private let policy = BackupPolicy(
        interval: 3_600,
        retention: 2_592_000,
        recoveryPointObjective: 3_600,
        recoveryTimeObjective: 14_400
    )

    @Test func encryptedArchiveRestoresExactPayload() throws {
        let service = try EncryptedBackupService(keyData: Data(repeating: 7, count: 32), policy: policy)
        let payload = Data("durable-state".utf8), now = Date(timeIntervalSince1970: 1_000)
        let archive = try service.createArchive(from: payload, dataClass: .financial, now: now)

        #expect(archive.sealedPayload != payload)
        #expect(try service.restore(archive, now: now.addingTimeInterval(1)) == payload)
        #expect(archive.plaintextSHA256.count == 32)
    }

    @Test func corruptionWrongKeyAndExpiredArchiveFailClosed() throws {
        let service = try EncryptedBackupService(keyData: Data(repeating: 7, count: 32), policy: policy)
        let other = try EncryptedBackupService(keyData: Data(repeating: 8, count: 32), policy: policy)
        let now = Date(timeIntervalSince1970: 2_000)
        let archive = try service.createArchive(from: Data("state".utf8), dataClass: .account, now: now)

        #expect(throws: BackupServiceError.decryptionFailed) {
            try other.restore(archive, now: now)
        }
        #expect(throws: BackupServiceError.invalidArchive) {
            try service.restore(archive, now: archive.expiresAt)
        }
    }

    @Test func policyAndRetentionAreDeterministic() throws {
        #expect(!BackupPolicy(interval: 100, retention: 50,
                             recoveryPointObjective: 100, recoveryTimeObjective: 1).isValid)
        let service = try EncryptedBackupService(keyData: Data(repeating: 1, count: 32), policy: policy)
        let now = Date(timeIntervalSince1970: 4_000)
        let old = try service.createArchive(from: Data([1]), dataClass: .operational,
                                            now: now.addingTimeInterval(-policy.retention))
        let current = try service.createArchive(from: Data([2]), dataClass: .configuration, now: now)
        #expect(service.retained([current, old], now: now).map(\.archiveID) == [current.archiveID])
    }
}
