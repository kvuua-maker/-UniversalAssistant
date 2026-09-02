import CryptoKit
import Foundation

public enum BackupDataClass: String, Codable, Sendable {
    case account, business, configuration, financial, operational
}

public struct BackupPolicy: Equatable, Sendable {
    public let interval: TimeInterval
    public let retention: TimeInterval
    public let recoveryPointObjective: TimeInterval
    public let recoveryTimeObjective: TimeInterval

    public init(interval: TimeInterval, retention: TimeInterval,
                recoveryPointObjective: TimeInterval, recoveryTimeObjective: TimeInterval) {
        self.interval = interval
        self.retention = retention
        self.recoveryPointObjective = recoveryPointObjective
        self.recoveryTimeObjective = recoveryTimeObjective
    }

    public var isValid: Bool {
        interval > 0 && retention >= interval &&
        recoveryPointObjective >= interval && recoveryTimeObjective > 0
    }
}

public struct EncryptedBackupArchive: Codable, Equatable, Sendable {
    public let archiveID: UUID
    public let dataClass: BackupDataClass
    public let createdAt: Date
    public let expiresAt: Date
    public let plaintextSHA256: Data
    public let sealedPayload: Data
}

public enum BackupServiceError: Error, Equatable, Sendable {
    case invalidPolicy, invalidKey, emptyPayload, invalidArchive, decryptionFailed
}

public struct EncryptedBackupService: Sendable {
    private let key: SymmetricKey
    public let policy: BackupPolicy

    public init(keyData: Data, policy: BackupPolicy) throws {
        guard policy.isValid else { throw BackupServiceError.invalidPolicy }
        guard keyData.count == 32 else { throw BackupServiceError.invalidKey }
        key = SymmetricKey(data: keyData)
        self.policy = policy
    }

    public func createArchive(
        from payload: Data,
        dataClass: BackupDataClass,
        now: Date = .now
    ) throws -> EncryptedBackupArchive {
        guard !payload.isEmpty else { throw BackupServiceError.emptyPayload }
        let sealed = try AES.GCM.seal(payload, using: key)
        guard let combined = sealed.combined else { throw BackupServiceError.invalidArchive }
        return .init(
            archiveID: UUID(),
            dataClass: dataClass,
            createdAt: now,
            expiresAt: now.addingTimeInterval(policy.retention),
            plaintextSHA256: Data(SHA256.hash(data: payload)),
            sealedPayload: combined
        )
    }

    public func restore(_ archive: EncryptedBackupArchive, now: Date = .now) throws -> Data {
        guard archive.expiresAt > archive.createdAt, archive.expiresAt > now,
              archive.plaintextSHA256.count == 32 else {
            throw BackupServiceError.invalidArchive
        }
        do {
            let box = try AES.GCM.SealedBox(combined: archive.sealedPayload)
            let plaintext = try AES.GCM.open(box, using: key)
            guard Data(SHA256.hash(data: plaintext)) == archive.plaintextSHA256 else {
                throw BackupServiceError.invalidArchive
            }
            return plaintext
        } catch let error as BackupServiceError {
            throw error
        } catch {
            throw BackupServiceError.decryptionFailed
        }
    }

    public func retained(_ archives: [EncryptedBackupArchive], now: Date = .now) -> [EncryptedBackupArchive] {
        archives.filter { $0.expiresAt > now }.sorted {
            $0.createdAt == $1.createdAt
                ? $0.archiveID.uuidString < $1.archiveID.uuidString
                : $0.createdAt < $1.createdAt
        }
    }
}
