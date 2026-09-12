@preconcurrency import CloudKit
import CryptoKit
import Darwin
import Foundation
import UIKit

enum CloudKitDiagnosticAudioError: Error, Equatable {
    case accountUnavailable
    case missingLocalAudio
    case malformedRemoteRecord
    case idempotencyConflict
    case checksumMismatch
}

struct CloudKitDiagnosticAudioReadback: Equatable, Sendable {
    let metadata: CloudKitDiagnosticAudioMetadata
    let downloadedByteCount: Int
    let downloadedSHA256: String
    var requestTrace: PhysicalDiagnosticSession? = nil
    var downloadedTraceByteCount: Int? = nil
    var downloadedTraceSHA256: String? = nil
}

protocol CloudKitDiagnosticAudioDatabase: Sendable {
    func save(_ upload: CloudKitDiagnosticAudioUpload, audioURL: URL) async throws
    func readBack(recordName: String) async throws -> CloudKitDiagnosticAudioReadback
    func allMetadata() async throws -> [CloudKitDiagnosticAudioMetadata]
    func delete(recordNames: [String]) async throws
    func setPinned(recordName: String, pinned: Bool) async throws
}

enum DiagnosticAudioSHA256 {
    static func hex(of url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return hex(of: data)
    }

    static func hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private enum DiagnosticDeviceModel {
    static var identifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return Mirror(reflecting: systemInfo.machine).children.reduce(into: "") { result, child in
            guard let value = child.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
    }
}

actor SystemCloudKitDiagnosticAudioDatabase: CloudKitDiagnosticAudioDatabase {
    static let containerIdentifier = "iCloud.com.universalassistant.app"
    static let recordType = "UADiagnosticAudio"

    private var resolvedContainer: CKContainer?
    private var resolvedDatabase: CKDatabase?

    init() {}

    func save(_ upload: CloudKitDiagnosticAudioUpload, audioURL: URL) async throws {
        let (container, database) = resolveCloudKit()
        guard try await container.accountStatus() == .available else {
            throw CloudKitDiagnosticAudioError.accountUnavailable
        }
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw CloudKitDiagnosticAudioError.missingLocalAudio
        }
        let traceData = upload.requestTrace.flatMap { try? JSONEncoder.diagnostic.encode($0) }

        let recordID = CKRecord.ID(recordName: upload.metadata.recordName)
        do {
            let existing = try await database.record(for: recordID)
            guard existing["audioSHA256"] as? String == upload.metadata.audioSHA256 else {
                throw CloudKitDiagnosticAudioError.idempotencyConflict
            }
            if let traceData {
                let traceSHA256 = DiagnosticAudioSHA256.hex(of: traceData)
                if let existingSHA256 = existing["requestTraceSHA256"] as? String,
                   existingSHA256 != traceSHA256 {
                    throw CloudKitDiagnosticAudioError.idempotencyConflict
                }
                if existing["requestTrace"] == nil {
                    existing["schemaVersion"] = NSNumber(value: 2)
                    existing["requestTrace"] = traceData as NSData
                    existing["requestTraceByteCount"] = NSNumber(value: traceData.count)
                    existing["requestTraceSHA256"] = traceSHA256 as NSString
                    _ = try await database.save(existing)
                }
            }
            return
        } catch let error as CKError where error.code == .unknownItem {
            // Expected first-upload path.
        }

        let metadata = upload.metadata
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record["schemaVersion"] = NSNumber(value: traceData == nil ? 1 : 2)
        record["requestID"] = metadata.requestID.uuidString.lowercased() as NSString
        record["diagnosticSessionID"] = metadata.diagnosticSessionID.uuidString.lowercased() as NSString
        record["physicalBuild"] = NSNumber(value: metadata.physicalBuild)
        record["appVersion"] = metadata.appVersion as NSString
        record["deviceModel"] = metadata.deviceModel as NSString
        record["systemVersion"] = metadata.systemVersion as NSString
        record["capturedAt"] = metadata.capturedAt as NSDate
        record["durationMilliseconds"] = NSNumber(value: metadata.durationMilliseconds)
        record["audioByteCount"] = NSNumber(value: metadata.audioByteCount)
        record["audioSHA256"] = metadata.audioSHA256 as NSString
        record["audioTruncated"] = NSNumber(value: metadata.audioTruncated)
        record["pinned"] = NSNumber(value: metadata.pinned)
        record["audio"] = CKAsset(fileURL: audioURL)
        if let traceData {
            record["requestTrace"] = traceData as NSData
            record["requestTraceByteCount"] = NSNumber(value: traceData.count)
            record["requestTraceSHA256"] = DiagnosticAudioSHA256.hex(of: traceData) as NSString
        }
        _ = try await database.save(record)
    }

    func readBack(recordName: String) async throws -> CloudKitDiagnosticAudioReadback {
        let (_, database) = resolveCloudKit()
        let record = try await database.record(for: CKRecord.ID(recordName: recordName))
        let metadata = try Self.metadata(from: record)
        guard let asset = record["audio"] as? CKAsset,
              let fileURL = asset.fileURL else {
            throw CloudKitDiagnosticAudioError.malformedRemoteRecord
        }
        let byteCount = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let checksum = try DiagnosticAudioSHA256.hex(of: fileURL)
        let traceData = record["requestTrace"] as? Data
        let trace = traceData.flatMap { try? JSONDecoder.diagnostic.decode(PhysicalDiagnosticSession.self, from: $0) }
        if let trace, trace.requestID != metadata.requestID {
            throw CloudKitDiagnosticAudioError.idempotencyConflict
        }
        return .init(
            metadata: metadata,
            downloadedByteCount: byteCount,
            downloadedSHA256: checksum,
            requestTrace: trace,
            downloadedTraceByteCount: traceData?.count,
            downloadedTraceSHA256: traceData.map { DiagnosticAudioSHA256.hex(of: $0) }
        )
    }

    func allMetadata() async throws -> [CloudKitDiagnosticAudioMetadata] {
        let (_, database) = resolveCloudKit()
        let keys = [
            "requestID", "diagnosticSessionID", "physicalBuild", "appVersion",
            "deviceModel", "systemVersion", "capturedAt", "durationMilliseconds",
            "audioByteCount", "audioSHA256", "audioTruncated", "pinned",
            "requestTraceByteCount", "requestTraceSHA256"
        ]
        let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
        var records: [CKRecord] = []
        var page = try await database.records(
            matching: query,
            desiredKeys: keys,
            resultsLimit: 200
        )
        records.append(contentsOf: page.matchResults.compactMap { _, result in try? result.get() })
        while let cursor = page.queryCursor {
            page = try await database.records(
                continuingMatchFrom: cursor,
                desiredKeys: keys,
                resultsLimit: 200
            )
            records.append(contentsOf: page.matchResults.compactMap { _, result in try? result.get() })
        }
        return records.compactMap { try? Self.metadata(from: $0) }
    }

    func delete(recordNames: [String]) async throws {
        let (_, database) = resolveCloudKit()
        for recordName in recordNames {
            do {
                _ = try await database.deleteRecord(withID: CKRecord.ID(recordName: recordName))
            } catch let error as CKError where error.code == .unknownItem {
                continue
            }
        }
    }

    func setPinned(recordName: String, pinned: Bool) async throws {
        let (_, database) = resolveCloudKit()
        let record = try await database.record(for: CKRecord.ID(recordName: recordName))
        record["pinned"] = NSNumber(value: pinned)
        _ = try await database.save(record)
    }

    private func resolveCloudKit() -> (CKContainer, CKDatabase) {
        if let resolvedContainer, let resolvedDatabase {
            return (resolvedContainer, resolvedDatabase)
        }
        let container = CKContainer(identifier: Self.containerIdentifier)
        resolvedContainer = container
        resolvedDatabase = container.publicCloudDatabase
        return (container, container.publicCloudDatabase)
    }

    private static func metadata(from record: CKRecord) throws -> CloudKitDiagnosticAudioMetadata {
        guard let requestText = record["requestID"] as? String,
              let requestID = UUID(uuidString: requestText),
              let sessionText = record["diagnosticSessionID"] as? String,
              let diagnosticSessionID = UUID(uuidString: sessionText),
              let physicalBuild = (record["physicalBuild"] as? NSNumber)?.intValue,
              let appVersion = record["appVersion"] as? String,
              let deviceModel = record["deviceModel"] as? String,
              let systemVersion = record["systemVersion"] as? String,
              let capturedAt = record["capturedAt"] as? Date,
              let durationMilliseconds = (record["durationMilliseconds"] as? NSNumber)?.intValue,
              let audioByteCount = (record["audioByteCount"] as? NSNumber)?.intValue,
              let audioSHA256 = record["audioSHA256"] as? String,
              let audioTruncated = (record["audioTruncated"] as? NSNumber)?.boolValue else {
            throw CloudKitDiagnosticAudioError.malformedRemoteRecord
        }
        return .init(
            recordName: record.recordID.recordName,
            requestID: requestID,
            diagnosticSessionID: diagnosticSessionID,
            physicalBuild: physicalBuild,
            appVersion: appVersion,
            deviceModel: deviceModel,
            systemVersion: systemVersion,
            capturedAt: capturedAt,
            durationMilliseconds: durationMilliseconds,
            audioByteCount: audioByteCount,
            audioSHA256: audioSHA256,
            audioTruncated: audioTruncated,
            pinned: (record["pinned"] as? NSNumber)?.boolValue ?? false,
            requestTraceByteCount: (record["requestTraceByteCount"] as? NSNumber)?.intValue,
            requestTraceSHA256: record["requestTraceSHA256"] as? String
        )
    }
}

/// CloudKit is an audio-only side-car for the existing diagnostics pipeline.
/// Local persistence always happens before this actor is called, and every
/// error is contained here so diagnostics cannot change command behavior.
actor CloudKitDiagnosticAudioDelivery {
    static let shared = CloudKitDiagnosticAudioDelivery()

    private let database: any CloudKitDiagnosticAudioDatabase
    private let localStore: PhysicalDiagnosticLocalStore
    private let enabled: @Sendable () async -> Bool
    private var flushing = false
    private var retryTask: Task<Void, Never>?

    init(
        database: any CloudKitDiagnosticAudioDatabase = SystemCloudKitDiagnosticAudioDatabase(),
        localStore: PhysicalDiagnosticLocalStore = .shared,
        enabled: @escaping @Sendable () async -> Bool = {
            let environment = ProcessInfo.processInfo.environment
            return environment["XCTestConfigurationFilePath"] == nil &&
                environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1"
        }
    ) {
        self.database = database
        self.localStore = localStore
        self.enabled = enabled
    }

    @discardableResult
    static func persistPending(
        _ session: PhysicalDiagnosticSession,
        localStore: PhysicalDiagnosticLocalStore,
        now: Date = .now
    ) -> Bool {
        guard session.feature == "voice",
              session.detailedDiagnosticsConsent == true,
              let requestID = session.requestID,
              let relativePath = session.diagnosticAudioRelativePath,
              let audioURL = localStore.diagnosticAudioURL(relativePath: relativePath),
              let fileSize = (try? audioURL.resourceValues(forKeys: [.fileSizeKey]).fileSize),
              fileSize > 0,
              let checksum = try? DiagnosticAudioSHA256.hex(of: audioURL) else { return false }
        guard let traceData = try? JSONEncoder.diagnostic.encode(session) else { return false }

        let metadata = CloudKitDiagnosticAudioMetadata(
            recordName: "ua-audio-\(requestID.uuidString.lowercased())",
            requestID: requestID,
            diagnosticSessionID: session.diagnosticSessionID ?? session.sessionID,
            physicalBuild: session.build,
            appVersion: session.appVersion,
            deviceModel: DiagnosticDeviceModel.identifier,
            systemVersion: session.osVersion,
            capturedAt: session.startedAt,
            durationMilliseconds: session.diagnosticAudioDurationMilliseconds ?? session.durationMilliseconds,
            audioByteCount: fileSize,
            audioSHA256: checksum,
            audioTruncated: session.diagnosticAudioTruncated ?? false,
            pinned: false,
            requestTraceByteCount: traceData.count,
            requestTraceSHA256: DiagnosticAudioSHA256.hex(of: traceData)
        )
        return localStore.addCloudKitAudioPending(.init(
            metadata: metadata,
            audioRelativePath: relativePath,
            attempts: 0,
            nextAttemptAt: now,
            state: .pending,
            lastErrorCategory: nil,
            requestTrace: session
        ))
    }

    func enqueue(_ session: PhysicalDiagnosticSession, now: Date = .now) async {
        guard Self.persistPending(session, localStore: localStore, now: now) else { return }
        await flush(now: now)
    }

    func flush(now: Date = .now) async {
        guard await enabled(), !flushing else { return }
        flushing = true
        defer { flushing = false }

        var queue = localStore.loadCloudKitAudioPending()
        while let index = queue.firstIndex(where: { $0.nextAttemptAt <= now }) {
            var upload = queue[index]
            guard let audioURL = localStore.diagnosticAudioURL(relativePath: upload.audioRelativePath) else {
                upload.attempts += 1
                upload.state = .retrying
                upload.lastErrorCategory = "missing_local_audio"
                upload.nextAttemptAt = now.addingTimeInterval(Self.retryDelay(attempts: upload.attempts))
                queue[index] = upload
                continue
            }
            do {
                try await database.save(upload, audioURL: audioURL)
                upload.state = .uploadedAwaitingVerification
                queue[index] = upload
                localStore.saveCloudKitAudioPending(queue)

                let readback = try await database.readBack(recordName: upload.metadata.recordName)
                let traceMatches: Bool
                if let expectedTraceSHA256 = upload.metadata.requestTraceSHA256 {
                    traceMatches = readback.requestTrace?.requestID == upload.metadata.requestID
                        && readback.downloadedTraceByteCount == upload.metadata.requestTraceByteCount
                        && readback.downloadedTraceSHA256 == expectedTraceSHA256
                } else {
                    traceMatches = true
                }
                guard readback.metadata.requestID == upload.metadata.requestID,
                      readback.metadata.diagnosticSessionID == upload.metadata.diagnosticSessionID,
                      readback.downloadedByteCount == upload.metadata.audioByteCount,
                      readback.downloadedSHA256 == upload.metadata.audioSHA256,
                      traceMatches else {
                    throw CloudKitDiagnosticAudioError.checksumMismatch
                }
                localStore.markCloudKitAudioVerified(upload, verifiedAt: now)
                queue.remove(at: index)
            } catch {
                upload.attempts += 1
                upload.state = .retrying
                upload.lastErrorCategory = String(describing: type(of: error))
                upload.nextAttemptAt = now.addingTimeInterval(Self.retryDelay(attempts: upload.attempts))
                queue[index] = upload
            }
        }
        localStore.saveCloudKitAudioPending(queue)

        do {
            try await enforceRemoteRetention()
        } catch {
            // Retention is retried at the next launch/enqueue. It never blocks
            // an already hash-verified local cleanup or the product request.
        }
        scheduleRetry(for: queue, now: now)
    }

    func setPinned(requestID: UUID, pinned: Bool) async throws {
        let recordName = "ua-audio-\(requestID.uuidString.lowercased())"
        try await database.setPinned(recordName: recordName, pinned: pinned)
        localStore.setCloudKitAudioPinned(requestID: requestID, pinned: pinned)
    }

    func pendingUploads() -> [CloudKitDiagnosticAudioUpload] {
        localStore.loadCloudKitAudioPending()
    }

    func verifiedReceipts() -> [CloudKitDiagnosticAudioReceipt] {
        localStore.cloudKitAudioReceipts()
    }

    private func enforceRemoteRetention() async throws {
        let localMetadata = localStore.cloudKitAudioReceipts().map(\.metadata)
        let remoteMetadata = (try? await database.allMetadata()) ?? []
        var metadataByRecordName: [String: CloudKitDiagnosticAudioMetadata] = [:]
        for item in localMetadata + remoteMetadata {
            metadataByRecordName[item.recordName] = item
        }
        let metadata = Array(metadataByRecordName.values)
        let retainedBuilds = Set(metadata.map(\.physicalBuild).sorted(by: >).reduce(into: [Int]()) { values, build in
            if !values.contains(build), values.count < 3 { values.append(build) }
        })
        let obsolete = metadata.filter { !retainedBuilds.contains($0.physicalBuild) && !$0.pinned }
        if !obsolete.isEmpty {
            let recordNames = Set(obsolete.map(\.recordName))
            try await database.delete(recordNames: Array(recordNames))
            localStore.removeCloudKitAudioReceipts(recordNames: recordNames)
        }
    }

    private func scheduleRetry(for queue: [CloudKitDiagnosticAudioUpload], now: Date) {
        retryTask?.cancel()
        guard let next = queue.map(\.nextAttemptAt).min() else {
            retryTask = nil
            return
        }
        let delay = max(1, min(900, next.timeIntervalSince(now)))
        retryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) }
            catch { return }
            guard let self else { return }
            await self.flush()
        }
    }

    private static func retryDelay(attempts: Int) -> TimeInterval {
        min(900, max(2, pow(2, Double(min(attempts, 9)))))
    }
}
