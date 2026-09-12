import CryptoKit
import Foundation
@testable import UniversalAssistant

actor CloudKitDiagnosticAudioTestDatabase: CloudKitDiagnosticAudioDatabase {
    private struct Stored: Sendable {
        var metadata: CloudKitDiagnosticAudioMetadata
        let data: Data
    }

    private var records: [String: Stored] = [:]
    private var shouldFailSaves: Bool
    private var shouldFailMetadataReads = false
    private var saveAttemptCount = 0

    init(failSaves: Bool) {
        shouldFailSaves = failSaves
    }

    func setFailSaves(_ value: Bool) {
        shouldFailSaves = value
    }

    func setFailMetadataReads(_ value: Bool) {
        shouldFailMetadataReads = value
    }

    func saveAttempts() -> Int { saveAttemptCount }
    func savedRecordCount() -> Int { records.count }

    func save(_ upload: CloudKitDiagnosticAudioUpload, audioURL: URL) async throws {
        saveAttemptCount += 1
        if shouldFailSaves { throw URLError(.notConnectedToInternet) }
        let data = try Data(contentsOf: audioURL)
        let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard checksum == upload.metadata.audioSHA256 else {
            throw CloudKitDiagnosticAudioError.checksumMismatch
        }
        if let existing = records[upload.metadata.recordName] {
            guard existing.metadata.audioSHA256 == checksum else {
                throw CloudKitDiagnosticAudioError.idempotencyConflict
            }
            return
        }
        records[upload.metadata.recordName] = .init(metadata: upload.metadata, data: data)
    }

    func readBack(recordName: String) async throws -> CloudKitDiagnosticAudioReadback {
        guard let stored = records[recordName] else {
            throw CloudKitDiagnosticAudioError.malformedRemoteRecord
        }
        let checksum = SHA256.hash(data: stored.data).map { String(format: "%02x", $0) }.joined()
        return .init(
            metadata: stored.metadata,
            downloadedByteCount: stored.data.count,
            downloadedSHA256: checksum
        )
    }

    func allMetadata() async throws -> [CloudKitDiagnosticAudioMetadata] {
        if shouldFailMetadataReads { throw URLError(.cannotParseResponse) }
        return records.values.map(\.metadata)
    }

    func delete(recordNames: [String]) async throws {
        for name in recordNames { records.removeValue(forKey: name) }
    }

    func setPinned(recordName: String, pinned: Bool) async throws {
        guard var stored = records[recordName] else {
            throw CloudKitDiagnosticAudioError.malformedRemoteRecord
        }
        stored.metadata.pinned = pinned
        records[recordName] = stored
    }

    func seed(build: Int, requestID: UUID) -> CloudKitDiagnosticAudioMetadata {
        let data = Data("build-\(build)".utf8)
        let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let metadata = CloudKitDiagnosticAudioMetadata(
            recordName: "ua-audio-\(requestID.uuidString.lowercased())",
            requestID: requestID,
            diagnosticSessionID: UUID(),
            physicalBuild: build,
            appVersion: "0.1.0",
            deviceModel: "iPhone12,8",
            systemVersion: "26.6.2",
            capturedAt: Date(timeIntervalSince1970: TimeInterval(build)),
            durationMilliseconds: 1_000,
            audioByteCount: data.count,
            audioSHA256: checksum,
            audioTruncated: false,
            pinned: false
        )
        records[metadata.recordName] = .init(metadata: metadata, data: data)
        return metadata
    }
}
