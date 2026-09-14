import Foundation

enum DiagnosticTerminalState: String, Codable, CaseIterable, Sendable {
    case success = "SUCCESS"
    case noResult = "NO_RESULT"
    case clarification = "CLARIFICATION"
    case permissionRequired = "PERMISSION_REQUIRED"
    case unsupported = "UNSUPPORTED"
    case providerRequired = "PROVIDER_REQUIRED"
    case timeout = "TIMEOUT"
    case cancelled = "CANCELLED"
    case error = "ERROR"
}

enum DiagnosticDeliveryStatus: String, Codable, Sendable {
    case localEvents = "LOCAL_EVENTS"
    case pendingUpload = "PENDING_UPLOAD"
    case uploaded = "UPLOADED"
    case serverRejected = "SERVER_REJECTED"
    case retrying = "RETRYING"
}

enum DiagnosticAnomalyClass: String, Codable, CaseIterable, Sendable {
    case asr = "ASR"
    case normalization = "NORMALIZATION"
    case languageDetection = "LANGUAGE_DETECTION"
    case morphology = "MORPHOLOGY"
    case structuredNumber = "STRUCTURED_NUMBER"
    case entityRecovery = "ENTITY_RECOVERY"
    case semanticFrame = "SEMANTIC_FRAME"
    case capabilitySelection = "CAPABILITY_SELECTION"
    case router = "ROUTER"
    case systemFirst = "SYSTEM_FIRST"
    case currentContext = "CURRENT_CONTEXT"
    case dependencyTransfer = "DEPENDENCY_TRANSFER"
    case permission = "PERMISSION"
    case executor = "EXECUTOR"
    case provider = "PROVIDER"
    case asyncLifecycle = "ASYNC_LIFECYCLE"
    case renderer = "RENDERER"
    case timeout = "TIMEOUT"
    case uncleanTermination = "UNCLEAN_TERMINATION"
    case unknown = "UNKNOWN"
}

enum DiagnosticEvidenceCertainty: String, Codable, Sendable {
    case confirmedRootCause = "CONFIRMED_ROOT_CAUSE"
    case probableFailureBoundary = "PROBABLE_FAILURE_BOUNDARY"
    case unknown = "UNKNOWN"
}

struct DiagnosticAnomaly: Codable, Equatable, Sendable {
    let anomalyClass: DiagnosticAnomalyClass
    let certainty: DiagnosticEvidenceCertainty
    let stage: String
    let reason: String
}

struct DiagnosticActiveRequestSnapshot: Codable, Equatable, Sendable {
    let diagnosticSessionID: UUID
    let requestID: UUID
    var requestGeneration: UInt64
    let build: Int
    var eventSequence: Int
    var lastStage: String
    var lastPRE: String?
    var lastPOST: String?
    var selectedCapability: String?
    var terminal: Bool
    var terminalState: DiagnosticTerminalState?
    var detailedDiagnosticsConsent: Bool = false
    var latestPartialTranscript: String? = nil
    var finalSpeechTranscript: String? = nil
    var normalizedTranscript: String? = nil
    var diagnosticAudioRelativePath: String? = nil
    var diagnosticAudioTruncated: Bool? = nil
    var diagnosticAudioDurationMilliseconds: Int? = nil
    var updatedAt: Date
}

struct DiagnosticQueuedUpload: Codable, Equatable, Sendable {
    let session: PhysicalDiagnosticSession
    var attempts: Int
    let expiresAt: Date
    var nextAttemptAt: Date
    var status: DiagnosticDeliveryStatus
    var lastHTTPStatus: Int?
    var errorCategory: String?
    var idempotencyKey: String { session.sessionID.uuidString.lowercased() }
}

struct DiagnosticDeliveryReceipt: Codable, Equatable, Sendable {
    let sessionID: UUID
    let uploadedAt: Date
    let eventCount: Int
}

enum CloudKitDiagnosticAudioUploadState: String, Codable, Sendable {
    case pending = "PENDING_UPLOAD"
    case retrying = "RETRYING"
    case uploadedAwaitingVerification = "UPLOADED_AWAITING_VERIFICATION"
}

struct CloudKitDiagnosticAudioMetadata: Codable, Equatable, Sendable {
    let recordName: String
    let requestID: UUID
    let diagnosticSessionID: UUID
    let physicalBuild: Int
    let appVersion: String
    let deviceModel: String
    let systemVersion: String
    let capturedAt: Date
    let durationMilliseconds: Int
    let audioByteCount: Int
    let audioSHA256: String
    let audioTruncated: Bool
    var pinned: Bool
    var requestTraceByteCount: Int? = nil
    var requestTraceSHA256: String? = nil
}

struct CloudKitDiagnosticAudioUpload: Codable, Equatable, Sendable {
    var metadata: CloudKitDiagnosticAudioMetadata
    let audioRelativePath: String?
    var attempts: Int
    var nextAttemptAt: Date
    var state: CloudKitDiagnosticAudioUploadState
    var lastErrorCategory: String?
    var requestTrace: PhysicalDiagnosticSession? = nil
    var idempotencyKey: String { metadata.recordName }
}

struct CloudKitDiagnosticAudioReceipt: Codable, Equatable, Sendable {
    let metadata: CloudKitDiagnosticAudioMetadata
    let verifiedAt: Date
}

struct DiagnosticBlackBoxStatus: Codable, Equatable, Sendable {
    let diagnosticsActive: Bool
    let diagnosticSessionID: UUID?
    let recordedRequests: Int
    let pendingUploads: Int
    let uploadedEvents: Int
    let lastRequestID: UUID?
    let lastStage: String?
    let lastAnomaly: DiagnosticAnomaly?
    let lastUncleanTermination: Date?
    let deliveryStatus: DiagnosticDeliveryStatus
    let appleDiagnosticCount: Int
}

/// File-backed persistence for the existing physical diagnostics pipeline.
/// All methods are fail-closed and nonthrowing to callers: diagnostics must
/// never alter the production command result or crash the app.
enum DiagnosticBoundaryName {
    static func forCommand(_ command: StructuredCommand) -> String? {
        switch command.intent {
        case .contactLookup, .contactCall: return "CONTACT_RESOLUTION"
        case .messageCompose: return "MESSAGE_COMPOSE"
        case .calendarCreate, .calendarQuery, .calendarUpdate, .calendarDelete: return "CALENDAR"
        case .reminderCreate, .reminderQuery, .reminderComplete, .reminderDelete: return "REMINDER"
        case .photoSearch: return command.entities["semantic_query"] == nil ? "PHOTOKIT" : "PHOTO_SEMANTIC_SEARCH"
        case .fileSearch: return "FILES"
        case .cameraCapture:
            return command.entities["capture_mode"] == "text_scan" ? "OCR" : nil
        case .translation: return "TRANSLATION"
        case .placeSearch, .restaurantSearch, .serviceSearch: return "MAPKIT_SEARCH"
        case .navigation, .routeSearch, .routeAwareSearch, .transportRoute: return "MAPKIT_ROUTE"
        case .multiStep: return "COMPOUND_STEP"
        case .currencyConversion, .productSearch, .fashionDiscovery, .groceryBasket, .reservation, .taxiSearch, .taxiCompare, .publicTransport, .ticketSearch, .ticketPurchaseHandoff, .hotelSearch, .travelPlan, .parcelTrack: return "PROVIDER"
        case .deviceAction:
            let action = command.entities["system_action"] ?? command.entities["quick_action"]
            switch action {
            case "timer": return "TIMER"
            case "alarm": return "ALARM"
            case "clipboard", "clipboard_write", "clipboard_read", "clipboard_open_url", "clipboard_copy_last": return "CLIPBOARD"
            default: return nil
            }
        default: return nil
        }
    }
}

final class PhysicalDiagnosticLocalStore: @unchecked Sendable {
    static let shared = PhysicalDiagnosticLocalStore()

    private let lock = NSLock()
    private let fileManager: FileManager
    let rootDirectory: URL
    private let activeFile: URL
    private let eventDirectory: URL
    private let audioDirectory: URL
    private let pendingFile: URL
    private let receiptFile: URL
    private let cloudKitAudioQueueFile: URL
    private let cloudKitAudioReceiptFile: URL
    private let anomalyFile: URL
    private let statusFile: URL
    private let lastUncleanFile: URL
    private let maxEventFileBytes: Int
    private let maxEventFiles: Int
    private let maxPending: Int
    private let maxReceipts: Int
    private let maxAudioFiles = 30

    init(
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default,
        maxEventFileBytes: Int = 512 * 1_024,
        maxEventFiles: Int = 4,
        maxPending: Int = 100,
        maxReceipts: Int = 200
    ) {
        self.fileManager = fileManager
        let base = rootDirectory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("UniversalAssistant", isDirectory: true)
            .appendingPathComponent("DiagnosticsBlackBox", isDirectory: true)
        self.rootDirectory = base
        activeFile = base.appendingPathComponent("active-request.json")
        eventDirectory = base.appendingPathComponent("events", isDirectory: true)
        audioDirectory = base.appendingPathComponent("audio", isDirectory: true)
        pendingFile = base.appendingPathComponent("pending-uploads.json")
        receiptFile = base.appendingPathComponent("uploaded-receipts.json")
        cloudKitAudioQueueFile = base.appendingPathComponent("cloudkit-audio-queue.json")
        cloudKitAudioReceiptFile = base.appendingPathComponent("cloudkit-audio-receipts.json")
        anomalyFile = base.appendingPathComponent("last-anomaly.json")
        statusFile = base.appendingPathComponent("delivery-status.json")
        lastUncleanFile = base.appendingPathComponent("last-unclean-request.json")
        self.maxEventFileBytes = max(4_096, maxEventFileBytes)
        self.maxEventFiles = max(2, maxEventFiles)
        self.maxPending = max(1, maxPending)
        self.maxReceipts = max(1, maxReceipts)
        lock.withLock { ensureDirectoriesLocked() }
    }

    func begin(_ snapshot: DiagnosticActiveRequestSnapshot) {
        lock.withLock {
            ensureDirectoriesLocked()
            writeAtomic(snapshot, to: activeFile)
            writeStatusLocked(.localEvents)
        }
    }

    func updateActive(
        sequence: Int,
        stage: String,
        pre: String? = nil,
        post: String? = nil,
        capability: String? = nil,
        generation: UInt64? = nil,
        terminal: DiagnosticTerminalState? = nil,
        detailedDiagnosticsConsent: Bool? = nil,
        latestPartialTranscript: String? = nil,
        finalSpeechTranscript: String? = nil,
        normalizedTranscript: String? = nil,
        diagnosticAudioRelativePath: String? = nil,
        diagnosticAudioTruncated: Bool? = nil,
        diagnosticAudioDurationMilliseconds: Int? = nil
    ) {
        lock.withLock {
            guard var value: DiagnosticActiveRequestSnapshot = decode(activeFile) else { return }
            value.eventSequence = max(value.eventSequence, sequence)
            value.lastStage = String(stage.prefix(128))
            if let pre {
                value.lastPRE = String(pre.prefix(128))
            }
            if let post {
                let boundedPost = String(post.prefix(128))
                value.lastPOST = boundedPost
                // A completed outer boundary can follow a completed nested
                // boundary. Keep the last durable pair internally coherent so
                // relaunch analysis never reports a missing nested POST after
                // the enclosing operation has itself returned.
                if boundedPost.hasSuffix("_POST") {
                    value.lastPRE = String(boundedPost.dropLast(5)) + "_PRE"
                }
            }
            if let capability { value.selectedCapability = String(capability.prefix(128)) }
            if let generation { value.requestGeneration = generation }
            if let terminal { value.terminal = true; value.terminalState = terminal }
            if let detailedDiagnosticsConsent { value.detailedDiagnosticsConsent = detailedDiagnosticsConsent }
            if let latestPartialTranscript { value.latestPartialTranscript = latestPartialTranscript }
            if let finalSpeechTranscript { value.finalSpeechTranscript = finalSpeechTranscript }
            if let normalizedTranscript { value.normalizedTranscript = normalizedTranscript }
            if let diagnosticAudioRelativePath { value.diagnosticAudioRelativePath = diagnosticAudioRelativePath }
            if let diagnosticAudioTruncated { value.diagnosticAudioTruncated = diagnosticAudioTruncated }
            if let diagnosticAudioDurationMilliseconds {
                value.diagnosticAudioDurationMilliseconds = max(0, diagnosticAudioDurationMilliseconds)
            }
            value.updatedAt = .now
            writeAtomic(value, to: activeFile)
        }
    }

    func append(_ event: PhysicalDiagnosticEvent, durable: Bool) {
        lock.withLock {
            ensureDirectoriesLocked()
            guard let encoded = try? JSONEncoder.diagnostic.encode(event) else { return }
            var line = encoded; line.append(0x0A)
            rotateIfNeededLocked(additionalBytes: line.count)
            let file = eventDirectory.appendingPathComponent("requests-0.jsonl")
            if !fileManager.fileExists(atPath: file.path) { _ = fileManager.createFile(atPath: file.path, contents: nil) }
            guard let handle = try? FileHandle(forWritingTo: file) else { return }
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
                if durable { try handle.synchronize() }
            } catch { return }
        }
    }

    func recentEvents(limit: Int = 1_000) -> [PhysicalDiagnosticEvent] {
        lock.withLock {
            let files = (0..<maxEventFiles).reversed().map { eventDirectory.appendingPathComponent("requests-\($0).jsonl") }
            let events = files.flatMap { file -> [PhysicalDiagnosticEvent] in
                guard let data = try? Data(contentsOf: file), let text = String(data: data, encoding: .utf8) else { return [] }
                // compactMap intentionally tolerates a partially written/corrupted tail.
                return text.split(separator: "\n").compactMap { line in
                    try? JSONDecoder.diagnostic.decode(PhysicalDiagnosticEvent.self, from: Data(line.utf8))
                }
            }
            return Array(events.suffix(max(0, limit)))
        }
    }

    func events(for requestID: UUID, limit: Int = 249) -> [PhysicalDiagnosticEvent] {
        let matching = recentEvents(limit: maxEventFiles * 10_000)
            .filter { $0.requestID == requestID }
            .sorted { lhs, rhs in
                if lhs.sequence == rhs.sequence { return lhs.timestamp < rhs.timestamp }
                return lhs.sequence < rhs.sequence
            }
        return Array(matching.suffix(max(0, limit)))
    }

    /// Stable private on-device destination for audio copied from the existing
    /// Speech tap. This method never starts capture or performs network I/O.
    func diagnosticAudioURL(for requestID: UUID) -> URL {
        lock.withLock {
            ensureDirectoriesLocked()
            pruneAudioLocked()
            return audioDirectory.appendingPathComponent("\(requestID.uuidString.lowercased()).caf")
        }
    }

    func diagnosticAudioRelativePath(for requestID: UUID) -> String {
        "audio/\(requestID.uuidString.lowercased()).caf"
    }
    func diagnosticAudioURL(relativePath: String) -> URL? {
        lock.withLock { validatedAudioURLLocked(relativePath: relativePath) }
    }

    @discardableResult
    func addCloudKitAudioPending(_ value: CloudKitDiagnosticAudioUpload) -> Bool {
        lock.withLock {
            var values: [CloudKitDiagnosticAudioUpload] = decode(cloudKitAudioQueueFile) ?? []
            let receipts: [CloudKitDiagnosticAudioReceipt] = decode(cloudKitAudioReceiptFile) ?? []
            if receipts.contains(where: { $0.metadata.recordName == value.metadata.recordName }) { return true }
            if values.contains(where: { $0.idempotencyKey == value.idempotencyKey }) { return true }
            guard values.count < maxPending else { return false }
            if let relativePath = value.audioRelativePath,
               validatedAudioURLLocked(relativePath: relativePath) == nil { return false }
            if value.audioRelativePath == nil,
               (value.metadata.audioByteCount != 0 || value.requestTrace == nil) { return false }
            values.append(value)
            writeAtomic(values, to: cloudKitAudioQueueFile)
            return true
        }
    }

    func loadCloudKitAudioPending() -> [CloudKitDiagnosticAudioUpload] {
        lock.withLock { decode(cloudKitAudioQueueFile) ?? [] }
    }

    func saveCloudKitAudioPending(_ values: [CloudKitDiagnosticAudioUpload]) {
        lock.withLock { writeAtomic(Array(values.prefix(maxPending)), to: cloudKitAudioQueueFile) }
    }

    func markCloudKitAudioVerified(_ value: CloudKitDiagnosticAudioUpload, verifiedAt: Date) {
        lock.withLock {
            var pending: [CloudKitDiagnosticAudioUpload] = decode(cloudKitAudioQueueFile) ?? []
            pending.removeAll { $0.idempotencyKey == value.idempotencyKey }
            writeAtomic(pending, to: cloudKitAudioQueueFile)
            var receipts: [CloudKitDiagnosticAudioReceipt] = decode(cloudKitAudioReceiptFile) ?? []
            if !receipts.contains(where: { $0.metadata.recordName == value.metadata.recordName }) {
                receipts.append(.init(metadata: value.metadata, verifiedAt: verifiedAt))
            }
            writeAtomic(Array(receipts.suffix(maxReceipts)), to: cloudKitAudioReceiptFile)
            if let relativePath = value.audioRelativePath,
               let audioURL = validatedAudioURLLocked(relativePath: relativePath) {
                try? fileManager.removeItem(at: audioURL)
            }
        }
    }

    func cloudKitAudioReceipts() -> [CloudKitDiagnosticAudioReceipt] {
        lock.withLock { decode(cloudKitAudioReceiptFile) ?? [] }
    }

    func removeCloudKitAudioReceipts(recordNames: Set<String>) {
        guard !recordNames.isEmpty else { return }
        lock.withLock {
            let receipts: [CloudKitDiagnosticAudioReceipt] = decode(cloudKitAudioReceiptFile) ?? []
            writeAtomic(
                receipts.filter { !recordNames.contains($0.metadata.recordName) },
                to: cloudKitAudioReceiptFile
            )
        }
    }

    func setCloudKitAudioPinned(requestID: UUID, pinned: Bool) {
        lock.withLock {
            var pending: [CloudKitDiagnosticAudioUpload] = decode(cloudKitAudioQueueFile) ?? []
            for index in pending.indices where pending[index].metadata.requestID == requestID {
                pending[index].metadata.pinned = pinned
            }
            writeAtomic(pending, to: cloudKitAudioQueueFile)

            var receipts: [CloudKitDiagnosticAudioReceipt] = decode(cloudKitAudioReceiptFile) ?? []
            receipts = receipts.map { receipt in
                guard receipt.metadata.requestID == requestID else { return receipt }
                var metadata = receipt.metadata
                metadata.pinned = pinned
                return .init(metadata: metadata, verifiedAt: receipt.verifiedAt)
            }
            writeAtomic(receipts, to: cloudKitAudioReceiptFile)
        }

    }
    func activeSnapshot() -> DiagnosticActiveRequestSnapshot? { lock.withLock { decode(activeFile) } }

    func clearTerminalActiveRequest() {
        lock.withLock {
            guard let value: DiagnosticActiveRequestSnapshot = decode(activeFile), value.terminal else { return }
            try? fileManager.removeItem(at: activeFile)
        }
    }

    func consumeUncleanActiveRequest() -> DiagnosticActiveRequestSnapshot? {
        lock.withLock {
            guard let value: DiagnosticActiveRequestSnapshot = decode(activeFile), !value.terminal else {
                if let terminal: DiagnosticActiveRequestSnapshot = decode(activeFile), terminal.terminal {
                    try? fileManager.removeItem(at: activeFile)
                }
                return nil
            }
            try? fileManager.removeItem(at: activeFile)
            writeAtomic(value, to: lastUncleanFile)
            return value
        }
    }

    func loadPending(now: Date = .now) -> [DiagnosticQueuedUpload] {
        lock.withLock {
            let decoded: [DiagnosticQueuedUpload] = decode(pendingFile) ?? []
            let active = decoded.filter { $0.expiresAt > now }
            if active != decoded { writeAtomic(active, to: pendingFile) }
            return active
        }
    }

    func savePending(_ values: [DiagnosticQueuedUpload]) {
        lock.withLock {
            let bounded = Array(values.suffix(maxPending))
            writeAtomic(bounded, to: pendingFile)
            let deliveryStatus: DiagnosticDeliveryStatus
            if bounded.isEmpty {
                deliveryStatus = .uploaded
            } else if bounded.contains(where: { $0.status == .retrying }) {
                deliveryStatus = .retrying
            } else if bounded.allSatisfy({ $0.status == .serverRejected }) {
                deliveryStatus = .serverRejected
            } else {
                deliveryStatus = .pendingUpload
            }
            writeStatusLocked(deliveryStatus)
        }
    }

    func addPending(_ value: DiagnosticQueuedUpload) {
        lock.withLock {
            var values: [DiagnosticQueuedUpload] = decode(pendingFile) ?? []
            let receipts: [DiagnosticDeliveryReceipt] = decode(receiptFile) ?? []
            guard !receipts.contains(where: { $0.sessionID == value.session.sessionID }),
                  !values.contains(where: { $0.idempotencyKey == value.idempotencyKey }) else { return }
            values.append(value)
            writeAtomic(Array(values.suffix(maxPending)), to: pendingFile)
            writeStatusLocked(.pendingUpload)
        }
    }

    func addReceipt(_ receipt: DiagnosticDeliveryReceipt) {
        lock.withLock {
            var values: [DiagnosticDeliveryReceipt] = decode(receiptFile) ?? []
            if !values.contains(where: { $0.sessionID == receipt.sessionID }) { values.append(receipt) }
            writeAtomic(Array(values.suffix(maxReceipts)), to: receiptFile)
            let pending: [DiagnosticQueuedUpload] = decode(pendingFile) ?? []
            if pending.isEmpty {
                writeStatusLocked(.uploaded)
            } else if pending.contains(where: { $0.status == .retrying }) {
                writeStatusLocked(.retrying)
            } else if pending.allSatisfy({ $0.status == .serverRejected }) {
                writeStatusLocked(.serverRejected)
            } else {
                writeStatusLocked(.pendingUpload)
            }
        }
    }

    func receipts() -> [DiagnosticDeliveryReceipt] { lock.withLock { decode(receiptFile) ?? [] } }

    func setDeliveryStatus(_ status: DiagnosticDeliveryStatus) { lock.withLock { writeStatusLocked(status) } }
    func deliveryStatus() -> DiagnosticDeliveryStatus { lock.withLock { decode(statusFile) ?? .localEvents } }

    func setLastAnomaly(_ anomaly: DiagnosticAnomaly?) {
        lock.withLock {
            if let anomaly { writeAtomic(anomaly, to: anomalyFile) }
            else { try? fileManager.removeItem(at: anomalyFile) }
        }
    }

    func lastAnomaly() -> DiagnosticAnomaly? { lock.withLock { decode(anomalyFile) } }

    func status() -> DiagnosticBlackBoxStatus {
        let latestEvent = recentEvents(limit: 1).last
        return lock.withLock {
            let active: DiagnosticActiveRequestSnapshot? = decode(activeFile)
            let pending: [DiagnosticQueuedUpload] = decode(pendingFile) ?? []
            let receipts: [DiagnosticDeliveryReceipt] = decode(receiptFile) ?? []
            let lastUnclean: DiagnosticActiveRequestSnapshot? = decode(lastUncleanFile)
            let appleDirectory = rootDirectory.appendingPathComponent("apple_diagnostics", isDirectory: true)
            let appleCount = ((try? fileManager.contentsOfDirectory(at: appleDirectory, includingPropertiesForKeys: nil)) ?? []).count
            let lastDiagnosticSessionID = active?.diagnosticSessionID ?? latestEvent?.diagnosticSessionID
            let uploadedEventCount = receipts.reduce(into: 0) { total, receipt in total += max(0, receipt.eventCount) }
            let lastRequestID = active?.requestID ?? latestEvent?.requestID
            let lastStage = active?.lastStage ?? latestEvent?.marker
            let lastAnomaly: DiagnosticAnomaly? = decode(anomalyFile)
            let deliveryStatus: DiagnosticDeliveryStatus = decode(statusFile) ?? .localEvents
            return DiagnosticBlackBoxStatus(
                diagnosticsActive: true,
                diagnosticSessionID: lastDiagnosticSessionID,
                recordedRequests: receipts.count + pending.count + (active == nil ? 0 : 1),
                pendingUploads: pending.count,
                uploadedEvents: uploadedEventCount,
                lastRequestID: lastRequestID,
                lastStage: lastStage,
                lastAnomaly: lastAnomaly,
                lastUncleanTermination: lastUnclean?.updatedAt,
                deliveryStatus: deliveryStatus,
                appleDiagnosticCount: appleCount
            )
        }
    }

    @discardableResult
    func addAppleDiagnostic(json: String, fingerprint: String) -> Bool {
        lock.withLock {
            let directory = rootDirectory.appendingPathComponent("apple_diagnostics", isDirectory: true)
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let safeFingerprint = String(fingerprint.filter { $0.isHexDigit }.prefix(64))
            guard safeFingerprint.count == 64, json.utf8.count <= 60_000 else { return false }
            let file = directory.appendingPathComponent("\(safeFingerprint).json")
            guard !fileManager.fileExists(atPath: file.path) else { return false }
            do { try Data(json.utf8).write(to: file, options: [.atomic, .completeFileProtection]) }
            catch { return false }
            let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            let ordered = files.sorted {
                let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhs > rhs
            }
            for stale in ordered.dropFirst(20) { try? fileManager.removeItem(at: stale) }
            return true
        }
    }

    func allFilesForExport() -> [URL] {
        lock.withLock {
            var values = [activeFile, pendingFile, receiptFile, cloudKitAudioQueueFile,
                          cloudKitAudioReceiptFile, anomalyFile, statusFile, lastUncleanFile]
            values += (0..<maxEventFiles).map { eventDirectory.appendingPathComponent("requests-\($0).jsonl") }
            values += (try? fileManager.contentsOfDirectory(at: audioDirectory, includingPropertiesForKeys: nil)) ?? []
            let appleDirectory = rootDirectory.appendingPathComponent("apple_diagnostics", isDirectory: true)
            values += (try? fileManager.contentsOfDirectory(at: appleDirectory, includingPropertiesForKeys: nil)) ?? []
            return values.filter { fileManager.fileExists(atPath: $0.path) }
        }
    }

    private func ensureDirectoriesLocked() {
        try? fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: eventDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var root = rootDirectory; try? root.setResourceValues(values)
    }

    private func pruneAudioLocked() {
        let files = (try? fileManager.contentsOfDirectory(
            at: audioDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let ordered = files.sorted {
            let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhs > rhs
        }
        let pending: [CloudKitDiagnosticAudioUpload] = decode(cloudKitAudioQueueFile) ?? []
        var protected = Set(pending.compactMap(\.audioRelativePath))
        if let active: DiagnosticActiveRequestSnapshot = decode(activeFile),
           let path = active.diagnosticAudioRelativePath {
            protected.insert(path)
        }
        for stale in ordered.dropFirst(maxAudioFiles) {
            let relative = "audio/\(stale.lastPathComponent)"
            if !protected.contains(relative) { try? fileManager.removeItem(at: stale) }
        }
    }

    private func validatedAudioURLLocked(relativePath: String) -> URL? {
        guard relativePath.hasPrefix("audio/"),
              !relativePath.contains(".."),
              relativePath.split(separator: "/").count == 2 else { return nil }
        let candidate = rootDirectory.appendingPathComponent(relativePath).standardizedFileURL
        guard candidate.deletingLastPathComponent() == audioDirectory.standardizedFileURL,
              fileManager.fileExists(atPath: candidate.path) else { return nil }
        return candidate
    }

    private func rotateIfNeededLocked(additionalBytes: Int) {
        let current = eventDirectory.appendingPathComponent("requests-0.jsonl")
        let size = (try? current.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size + additionalBytes > maxEventFileBytes else { return }
        let oldest = eventDirectory.appendingPathComponent("requests-\(maxEventFiles - 1).jsonl")
        try? fileManager.removeItem(at: oldest)
        if maxEventFiles > 1 {
            for index in stride(from: maxEventFiles - 2, through: 0, by: -1) {
                let source = eventDirectory.appendingPathComponent("requests-\(index).jsonl")
                let destination = eventDirectory.appendingPathComponent("requests-\(index + 1).jsonl")
                if fileManager.fileExists(atPath: source.path) { try? fileManager.moveItem(at: source, to: destination) }
            }
        }
    }

    private func writeStatusLocked(_ status: DiagnosticDeliveryStatus) { writeAtomic(status, to: statusFile) }

    private func writeAtomic<Value: Encodable>(_ value: Value, to url: URL) {
        guard let data = try? JSONEncoder.diagnostic.encode(value) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    private func decode<Value: Decodable>(_ url: URL) -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.diagnostic.decode(Value.self, from: data)
    }
}

enum DiagnosticAnomalyAnalyzer {
    static func analyze(events: [PhysicalDiagnosticEvent], active: DiagnosticActiveRequestSnapshot? = nil) -> DiagnosticAnomaly? {
        if let active, !active.terminal {
            let stage = active.lastPRE ?? active.lastStage
            let missing = active.lastPRE.flatMap { pre in active.lastPOST == pairedPost(for: pre) ? nil : pairedPost(for: pre) }
            return .init(anomalyClass: .uncleanTermination, certainty: .probableFailureBoundary,
                         stage: stage, reason: missing.map { "missing_expected_post:\($0)" } ?? "request_not_terminal")
        }

        for event in events.sorted(by: { $0.sequence < $1.sequence }) {
            if isSpeechFailure(event) {
                return .init(anomalyClass: .asr, certainty: .probableFailureBoundary,
                             stage: event.marker, reason: explicitReason(event, fallback: "speech_pipeline_error"))
            }
            if event.marker == "generic_web_selected", event.attributes["selected"] == "true",
               !isDeliberateWebSelection(event.attributes["reason"]) {
                return .init(anomalyClass: .systemFirst, certainty: .probableFailureBoundary,
                             stage: event.marker, reason: event.attributes["reason"] ?? "unexpected_generic_web_selection")
            }
            if isExplicitFailure(event) {
                return .init(anomalyClass: anomalyClass(for: event.marker), certainty: .probableFailureBoundary,
                             stage: event.marker, reason: explicitReason(event, fallback: "explicit_stage_failure"))
            }
        }

        if let timeout = events.first(where: { $0.marker == "terminal_request_state" && $0.attributes["state"] == DiagnosticTerminalState.timeout.rawValue }) {
            return .init(anomalyClass: .timeout, certainty: .probableFailureBoundary, stage: timeout.marker, reason: "terminal_timeout")
        }
        if let terminal = events.first(where: { $0.marker == "terminal_request_state" && $0.attributes["state"] == DiagnosticTerminalState.error.rawValue }) {
            if let boundary = lastUnmatchedBoundary(in: events) {
                return .init(anomalyClass: anomalyClass(for: boundary.marker), certainty: .probableFailureBoundary,
                             stage: boundary.marker, reason: "missing_expected_post:\(pairedPost(for: boundary.marker) ?? "unknown")")
            }
            return .init(anomalyClass: .unknown, certainty: .unknown, stage: terminal.marker, reason: "terminal_error_without_stage_evidence")
        }
        return nil
    }

    static func pairedPost(for pre: String) -> String? {
        guard pre.hasSuffix("_PRE") else { return nil }
        return String(pre.dropLast(4)) + "_POST"
    }

    private static func isSpeechFailure(_ event: PhysicalDiagnosticEvent) -> Bool {
        if event.marker == "voice_start_failed" { return true }
        guard event.marker == "recognition_callback" else { return false }
        return (event.attributes["error_code"].flatMap(Int.init) ?? 0) != 0 ||
            (event.attributes["error_domain"].map { $0 != "none" } ?? false)
    }

    private static func isDeliberateWebSelection(_ reason: String?) -> Bool {
        guard let reason else { return false }
        return ["structured_general_or_web_intent", "deliberate_provider_or_general_information_fallback"].contains(reason)
    }

    private static func isExplicitFailure(_ event: PhysicalDiagnosticEvent) -> Bool {
        if event.marker == "execution_failed" {
            return event.attributes["reason"] != "external_provider_required"
        }
        if event.marker.hasSuffix("_failed") { return true }
        if (event.attributes["error_code"].flatMap(Int.init) ?? 0) != 0 { return true }
        return ["error", "failed"].contains(event.attributes["status"]?.lowercased() ?? "")
    }

    private static func explicitReason(_ event: PhysicalDiagnosticEvent, fallback: String) -> String {
        event.attributes["reason"] ?? event.attributes["error_type"] ?? event.attributes["error_domain"] ?? fallback
    }

    private static func lastUnmatchedBoundary(in events: [PhysicalDiagnosticEvent]) -> PhysicalDiagnosticEvent? {
        for event in events.sorted(by: { $0.sequence > $1.sequence }) where event.marker.hasSuffix("_PRE") {
            guard let post = pairedPost(for: event.marker) else { continue }
            if !events.contains(where: { $0.sequence > event.sequence && $0.marker == post }) { return event }
        }
        return nil
    }

    private static func anomalyClass(for marker: String) -> DiagnosticAnomalyClass {
        switch marker {
        case "recognition_callback", "voice_start_failed", "SPEECH_START_PRE", "SPEECH_START_POST":
            return .asr
        case "normalization": return .normalization
        case "language_detection": return .languageDetection
        case "morphology": return .morphology
        case "structured_number_reconstruction": return .structuredNumber
        case "entity_recovery", "entity_domain", "entity_candidates", "entity_confidence": return .entityRecovery
        case "canonical_semantic_frame": return .semanticFrame
        case "candidate_capabilities", "selected_capability": return .capabilitySelection
        case "router_received", "router_accepted", "router_rejected": return .router
        case "system_first_decision", "generic_web_selected": return .systemFirst
        case "current_context_input", "CURRENTCONTEXT_PRE", "CURRENTCONTEXT_POST": return .currentContext
        case "compound_step", "dependency_input_type", "dependency_output_type", "COMPOUND_STEP_PRE", "COMPOUND_STEP_POST":
            return .dependencyTransfer
        case "permission_state": return .permission
        case "PROVIDER_PRE", "PROVIDER_POST", "weatherkit_request_failed", "weather_context_failed":
            return .provider
        case "RENDERER_ACTION_PRE", "RENDERER_ACTION_POST": return .renderer
        case "audio_interruption", "scene_transition", "stale_start_suppressed", "stale_stop_suppressed", "stale_recognition_suppressed":
            return .asyncLifecycle
        default: return .executor
        }
    }
}


enum DiagnosticExportError: Error {
    case invalidEntryName
    case entryTooLarge
}

/// Emergency-only export of the same durable black-box store used by VPS delivery.
/// The archive uses the public ZIP container format with stored (uncompressed)
/// entries so no second diagnostics database or third-party dependency is needed.
enum DiagnosticExportBuilder {
    static func makeBuild32Package(store: PhysicalDiagnosticLocalStore = .shared, now: Date = .now) throws -> URL {
        let status = store.status()
        let build = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
        let timestampFormatter = DateFormatter()
        timestampFormatter.locale = Locale(identifier: "en_US_POSIX")
        timestampFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UniversalAssistantDiagnosticsExports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(
            "UniversalAssistant_Diagnostics_Build\(build)_\(timestampFormatter.string(from: now)).zip"
        )

        let encoder = JSONEncoder.diagnostic
        var entries: [(String, Data)] = []
        let manifest: [String: String] = [
            "product": "UniversalAssistant",
            "schema": "2",
            "build": String(build),
            "createdAt": ISO8601DateFormatter().string(from: now),
            "commandAudioStored": "locally_when_detailed_diagnostics_enabled",
            "primaryDelivery": "firebase_crashlytics_text"
        ]
        entries.append(("manifest.json", try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])))

        var requestLog = Data()
        for event in store.recentEvents(limit: 10_000) {
            requestLog.append(try encoder.encode(event))
            requestLog.append(0x0A)
        }
        entries.append(("requests.jsonl", requestLog))
        if let anomaly = status.lastAnomaly {
            entries.append(("analysis_summary.json", try encoder.encode(anomaly)))
        } else {
            entries.append(("analysis_summary.json", Data(#"{"anomaly":"none"}"#.utf8)))
        }

        let localFiles = store.allFilesForExport()
        if let lastUnclean = localFiles.first(where: { $0.lastPathComponent == "last-unclean-request.json" }) {
            entries.append(("last_unclean_request.json", try Data(contentsOf: lastUnclean)))
        } else {
            entries.append(("last_unclean_request.json", Data(#"{"status":"none"}"#.utf8)))
        }
        entries.append(("vps_delivery_status.json", try encoder.encode(status)))

        let appleFiles = localFiles.filter { $0.deletingLastPathComponent().lastPathComponent == "apple_diagnostics" }
        if appleFiles.isEmpty {
            entries.append(("apple_diagnostics/status.json", Data(#"{"status":"none"}"#.utf8)))
        } else {
            for file in appleFiles.prefix(20) {
                entries.append(("apple_diagnostics/\(file.lastPathComponent)", try Data(contentsOf: file)))
            }
        }

        let audioFiles = localFiles.filter { $0.deletingLastPathComponent().lastPathComponent == "audio" }
        for file in audioFiles.prefix(30) {
            entries.append(("audio/\(file.lastPathComponent)", try Data(contentsOf: file)))
        }
        let summary = """
        Діагностика UniversalAssistant
        Build: \(build)
        Записаних запитів: \(status.recordedRequests)
        Очікують надсилання: \(status.pendingUploads)
        Підтверджено VPS: \(status.uploadedEvents)
        Останній етап: \(status.lastStage ?? "немає")
        Остання аномалія: \(status.lastAnomaly?.anomalyClass.rawValue ?? "немає")
        Apple diagnostics: \(status.appleDiagnosticCount)
        Command audio: локально, якщо детальна діагностика ввімкнена
        """
        entries.append(("human_summary_uk.txt", Data(summary.utf8)))

        let archive = try StoredZIPArchive.make(entries: entries)
        try archive.write(to: destination, options: [.atomic, .completeFileProtection])
        let stale = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .sorted {
                let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhs > rhs
            }
        for file in stale.dropFirst(5) { try? FileManager.default.removeItem(at: file) }
        return destination
    }
}

private enum StoredZIPArchive {
    private struct CentralEntry {
        let name: Data
        let crc32: UInt32
        let size: UInt32
        let localOffset: UInt32
    }

    static func make(entries: [(String, Data)]) throws -> Data {
        var archive = Data()
        var centralEntries: [CentralEntry] = []
        for (name, contents) in entries {
            guard !name.hasPrefix("/"), !name.contains(".."), let nameData = name.data(using: .utf8), nameData.count <= Int(UInt16.max) else {
                throw DiagnosticExportError.invalidEntryName
            }
            guard contents.count <= Int(UInt32.max), archive.count <= Int(UInt32.max) else {
                throw DiagnosticExportError.entryTooLarge
            }
            let crc = crc32(contents)
            let offset = UInt32(archive.count)
            archive.appendLittleEndian(UInt32(0x04034b50))
            archive.appendLittleEndian(UInt16(20))
            archive.appendLittleEndian(UInt16(0x0800))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(crc)
            archive.appendLittleEndian(UInt32(contents.count))
            archive.appendLittleEndian(UInt32(contents.count))
            archive.appendLittleEndian(UInt16(nameData.count))
            archive.appendLittleEndian(UInt16(0))
            archive.append(nameData)
            archive.append(contents)
            centralEntries.append(.init(name: nameData, crc32: crc, size: UInt32(contents.count), localOffset: offset))
        }

        guard archive.count <= Int(UInt32.max), centralEntries.count <= Int(UInt16.max) else {
            throw DiagnosticExportError.entryTooLarge
        }
        let centralOffset = UInt32(archive.count)
        var central = Data()
        for entry in centralEntries {
            central.appendLittleEndian(UInt32(0x02014b50))
            central.appendLittleEndian(UInt16(20))
            central.appendLittleEndian(UInt16(20))
            central.appendLittleEndian(UInt16(0x0800))
            central.appendLittleEndian(UInt16(0))
            central.appendLittleEndian(UInt16(0))
            central.appendLittleEndian(UInt16(0))
            central.appendLittleEndian(entry.crc32)
            central.appendLittleEndian(entry.size)
            central.appendLittleEndian(entry.size)
            central.appendLittleEndian(UInt16(entry.name.count))
            central.appendLittleEndian(UInt16(0))
            central.appendLittleEndian(UInt16(0))
            central.appendLittleEndian(UInt16(0))
            central.appendLittleEndian(UInt16(0))
            central.appendLittleEndian(UInt32(0))
            central.appendLittleEndian(entry.localOffset)
            central.append(entry.name)
        }
        guard central.count <= Int(UInt32.max) else { throw DiagnosticExportError.entryTooLarge }
        archive.append(central)
        archive.appendLittleEndian(UInt32(0x06054b50))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(centralEntries.count))
        archive.appendLittleEndian(UInt16(centralEntries.count))
        archive.appendLittleEndian(UInt32(central.count))
        archive.appendLittleEndian(centralOffset)
        archive.appendLittleEndian(UInt16(0))
        return archive
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var value = UInt32.max
        for byte in data {
            value ^= UInt32(byte)
            for _ in 0..<8 {
                value = (value >> 1) ^ (UInt32(0xedb88320) & (0 &- (value & 1)))
            }
        }
        return value ^ UInt32.max
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
