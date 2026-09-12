import AVFoundation
import CryptoKit
import Speech
import FirebaseCore
import FirebaseCrashlytics
import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Crashlytics diagnostics side-car", .serialized)
struct CrashlyticsDiagnosticsIntegrationTests {
    @Test func detailedTraceUsesExistingIdentityAndEmitsOneTerminalNonFatal() throws {
        let client = RecordingCrashlyticsClient()
        let bridge = CrashlyticsDiagnosticBridge(client: client, readiness: { true })
        let diagnosticSessionID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let requestID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let identity = CrashlyticsDiagnosticRequestIdentity(
            diagnosticSessionID: diagnosticSessionID,
            requestID: requestID,
            generation: 37,
            appVersion: "0.1.0",
            build: 32
        )

        bridge.beginRequest(identity, inputMode: "voice")
        bridge.recordTranscript(
            "Знайди взуття Baldinini поруч і відкрий https://example.com/catalog",
            normalized: false,
            sequence: 3,
            identity: identity,
            detailedDiagnosticsEnabled: true
        )
        bridge.recordTranscript(
            "знайти взуття baldinini поруч і відкрити https://example.com/catalog",
            normalized: true,
            sequence: 5,
            identity: identity,
            detailedDiagnosticsEnabled: true
        )
        bridge.recordEvent(
            "canonical_semantic_frame",
            details: "action=product_search object=shoes location=nearby",
            sequence: 6,
            identity: identity
        )
        bridge.recordEvent(
            "selected_capability",
            details: "capability=productSearch route=provider",
            sequence: 8,
            identity: identity
        )
        bridge.recordEvent(
            "generic_web_selected",
            details: "selected=false reason=canonical_provider_request",
            sequence: 9,
            identity: identity
        )
        bridge.recordEvent(
            "PROVIDER_PRE",
            details: "provider=product_catalog capability=productSearch",
            sequence: 10,
            identity: identity
        )
        bridge.recordEvent(
            "PROVIDER_POST",
            details: "provider=product_catalog result=provider_required",
            sequence: 11,
            identity: identity
        )

        var session = makeSession(
            diagnosticSessionID: diagnosticSessionID,
            requestID: requestID,
            generation: 37,
            terminalState: .providerRequired,
            detailed: true
        )
        session.finalSpeechTranscript = "Знайди взуття Baldinini поруч і відкрий https://example.com/catalog"
        session.normalizedTranscript = "знайти взуття baldinini поруч і відкрити https://example.com/catalog"
        bridge.recordTerminal(session)
        bridge.recordTerminal(session)

        #expect(client.value(for: "ua_request_id") == requestID.uuidString)
        #expect(client.value(for: "ua_request_generation") == "37")
        #expect(client.value(for: "ua_capability") == "productSearch")
        #expect(client.value(for: "ua_generic_web") == "false")
        #expect(client.value(for: "ua_executor") == "product_catalog")
        #expect(client.value(for: "ua_terminal_state") == DiagnosticTerminalState.providerRequired.rawValue)
        let traceLogs = client.logs
        let hasFinalTranscript = traceLogs.contains { $0.contains("Знайди взуття Baldinini поруч") }
        let hasNormalizedTranscript = traceLogs.contains { $0.contains("знайти взуття baldinini поруч") }
        let hasDiagnosticURL = traceLogs.contains { $0.contains("https://example.com/catalog") }
        #expect(hasFinalTranscript)
        #expect(hasNormalizedTranscript)
        #expect(hasDiagnosticURL)
        #expect(client.errors.count == 1)
        #expect(client.errors.first?.domain == "UA_DIAGNOSTIC_COMMAND_TRACE")
    }

    @Test func basicAlwaysOnTraceWithholdsDetailedTextAndTerminalNonFatalWithoutConsent() throws {
        let client = RecordingCrashlyticsClient()
        let bridge = CrashlyticsDiagnosticBridge(client: client, readiness: { true })
        let identity = CrashlyticsDiagnosticRequestIdentity(
            diagnosticSessionID: UUID(),
            requestID: UUID(),
            generation: 4,
            appVersion: "0.1.0",
            build: 32
        )

        bridge.beginRequest(identity, inputMode: "text")
        bridge.recordEvent(
            "selected_capability",
            details: "capability=storageStatus",
            sequence: 2,
            identity: identity
        )
        bridge.recordTranscript(
            "секретний тестовий текст",
            normalized: false,
            sequence: 3,
            identity: identity,
            detailedDiagnosticsEnabled: false
        )
        bridge.recordTerminal(
            makeSession(
                diagnosticSessionID: identity.diagnosticSessionID,
                requestID: identity.requestID,
                generation: identity.generation,
                terminalState: .success,
                detailed: false
            )
        )

        let basicLogs = client.logs
        let hasRequestBegin = basicLogs.contains { $0.contains("marker=REQUEST_BEGIN") }
        let hasDetailedDisabledMarker = basicLogs.contains { $0.contains("marker=FINAL_SPEECH_TRANSCRIPT detailed=false") }
        let leakedDetailedText = basicLogs.contains { $0.contains("секретний тестовий текст") }
        #expect(hasRequestBegin)
        #expect(hasDetailedDisabledMarker)
        #expect(leakedDetailedText == false)
        #expect(client.value(for: "ua_transcript") == "")
        #expect(client.errors.isEmpty)
    }

    @Test func credentialRedactionPreservesDiagnosticEntitiesAndReportsTruncation() {
        let client = RecordingCrashlyticsClient()
        let bridge = CrashlyticsDiagnosticBridge(client: client, readiness: { true })
        let identity = CrashlyticsDiagnosticRequestIdentity(
            diagnosticSessionID: UUID(),
            requestID: UUID(),
            generation: 9,
            appVersion: "0.1.0",
            build: 32
        )
        let longText = "Напиши Марії через WhatsApp про Baldinini; api_key=AIzaabcdefghijklmnopqrstuvwxyz012345 " +
            String(repeating: "довгий-текст ", count: 1_400)

        bridge.recordTranscript(
            longText,
            normalized: false,
            sequence: 2,
            identity: identity,
            detailedDiagnosticsEnabled: true
        )

        let redactionLogs = client.logs
        let preservesEntities = redactionLogs.contains { $0.contains("Марії через WhatsApp про Baldinini") }
        let leakedAPIKey = redactionLogs.contains { $0.contains("AIzaabcdefghijklmnopqrstuvwxyz012345") }
        let hasSecretMarker = redactionLogs.contains { $0.contains("[SECRET_REDACTED]") || $0.contains("[API_KEY_REDACTED]") }
        let hasTruncationMarker = redactionLogs.contains { $0.contains("TRUNCATED_BY_PROVIDER_LIMIT") }
        #expect(preservesEntities)
        #expect(leakedAPIKey == false)
        #expect(hasSecretMarker)
        #expect(hasTruncationMarker)
        #expect(client.value(for: "ua_transcript_truncated") == "true")
        #expect(Int(client.value(for: "ua_transcript_length") ?? "0") ?? 0 > 12_000)
    }

    @Test @MainActor func canonicalReporterForwardsTheRealOrderedTraceWithoutSecondIdentity() throws {
        let recorder = RecordingDiagnosticRecorder()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ua-crashlytics-sidecar-\(UUID().uuidString)", isDirectory: true)
        let report = LocalVoiceDiagnosticReport(
            defaults: defaults,
            persistenceKey: "firebase-sidecar-test",
            localStore: PhysicalDiagnosticLocalStore(rootDirectory: root),
            crashlyticsRecorder: recorder
        )
        report.detailedDiagnosticsEnabled = true
        report.beginHomeRequest(generation: 73)
        report.recordSpeechTranscript("Десь би випити чаю неподалік", isFinal: true)
        report.recordNormalizedTranscript("десь би випити чаю неподалік")
        report.record("canonical_semantic_frame", "action=place_search category=tea location=nearby")
        report.record("selected_capability", "capability=placeSearch route=MapKit")
        report.recordBoundaryPre("MAPKIT_SEARCH", "capability=placeSearch")
        report.recordBoundaryPost("MAPKIT_SEARCH", "capability=placeSearch result=success")
        report.record("visible_result", "kind=place_list")
        let session = try #require(report.completedSession())

        #expect(recorder.begins.count == 1)
        #expect(recorder.begins.first?.identity.requestID == session.requestID)
        #expect(recorder.begins.first?.identity.generation == 73)
        let transcriptTexts = recorder.transcripts.map(\.text)
        #expect(transcriptTexts.count == 2)
        #expect(transcriptTexts.first == "Десь би випити чаю неподалік")
        #expect(transcriptTexts.last == "десь би випити чаю неподалік")
        let transcriptsAreDetailed = recorder.transcripts.allSatisfy(\.detailed)
        let eventMarkers = recorder.events.map(\.marker)
        let hasSemanticFrame = eventMarkers.contains("canonical_semantic_frame")
        let hasSelectedCapability = eventMarkers.contains("selected_capability")
        let hasMapKitPre = eventMarkers.contains("MAPKIT_SEARCH_PRE")
        let hasMapKitPost = eventMarkers.contains("MAPKIT_SEARCH_POST")
        let terminalThenRequestEnd = Array(eventMarkers.suffix(2)) == ["terminal_request_state", "request_end"]
        let allEventsOwned = recorder.events.allSatisfy { $0.identity.requestID == session.requestID }
        let terminalRequestIDsMatch = recorder.terminals.map(\.requestID) == [session.requestID]
        #expect(transcriptsAreDetailed)
        #expect(hasSemanticFrame)
        #expect(hasSelectedCapability)
        #expect(hasMapKitPre)
        #expect(hasMapKitPost)
        #expect(terminalThenRequestEnd)
        #expect(allEventsOwned)
        #expect(terminalRequestIDsMatch)
    }

    @Test func unavailableCrashlyticsClientCannotAffectProductionFlow() {
        let client = RecordingCrashlyticsClient()
        let bridge = CrashlyticsDiagnosticBridge(client: client, readiness: { false })
        let identity = CrashlyticsDiagnosticRequestIdentity(
            diagnosticSessionID: UUID(),
            requestID: UUID(),
            generation: 1,
            appVersion: "0.1.0",
            build: 32
        )
        bridge.beginRequest(identity, inputMode: "voice")
        bridge.recordEvent("EXECUTOR_PRE", details: "capability=contactCall", sequence: 1, identity: identity)
        bridge.recordTranscript(
            "подзвони контакту",
            normalized: false,
            sequence: 2,
            identity: identity,
            detailedDiagnosticsEnabled: true
        )
        #expect(client.logs.isEmpty)
        #expect(client.values.isEmpty)
        #expect(client.errors.isEmpty)
    }
    @Test func metricKitSideCarUsesExistingCrashlyticsChannelWithCorrelationAndBounds() {
        let client = RecordingCrashlyticsClient()
        let bridge = CrashlyticsDiagnosticBridge(client: client, readiness: { true })
        let identity = CrashlyticsDiagnosticRequestIdentity(
            diagnosticSessionID: UUID(),
            requestID: UUID(),
            generation: 81,
            appVersion: "0.1.0",
            build: 35
        )
        let payload = "{\"hangDiagnostic\":\"\(String(repeating: "frame ", count: 3_000))\"}"

        bridge.recordMetricKitPayload(
            kind: "diagnostic",
            fingerprint: String(repeating: "a", count: 64),
            payload: payload,
            identity: identity
        )

        #expect(client.value(for: "ua_request_id") == identity.requestID.uuidString)
        #expect(client.value(for: "ua_request_generation") == "81")
        #expect(client.value(for: "ua_metrickit_kind") == "diagnostic")
        #expect(client.value(for: "ua_metrickit_fingerprint") == String(repeating: "a", count: 64))
        #expect(client.logs.contains { $0.contains("marker=METRICKIT_PAYLOAD_RECEIVED") })
        #expect(client.logs.contains { $0.contains("TRUNCATED_BY_PROVIDER_LIMIT") })
        #expect(client.errors.map(\.domain) == ["UA_METRICKIT_PAYLOAD"])
    }


    @Test @MainActor func oneVoiceRequestIsLocallyDurableAndReconstructableFromCrashlyticsAndCloudKit() async throws {
        let client = RecordingCrashlyticsClient()
        let bridge = CrashlyticsDiagnosticBridge(client: client, readiness: { true })
        let defaults = UserDefaults(suiteName: "ua-diagnostics-e2e-\(UUID().uuidString)")!
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ua-diagnostics-e2e-\(UUID().uuidString)", isDirectory: true)
        let store = PhysicalDiagnosticLocalStore(rootDirectory: root)
        let report = LocalVoiceDiagnosticReport(
            defaults: defaults,
            persistenceKey: "targeted-e2e",
            localStore: store,
            crashlyticsRecorder: bridge
        )
        report.detailedDiagnosticsEnabled = true
        report.reset()
        let requestID = report.currentRequestIdentifier

        report.record("mic_tap", "source=targeted_e2e")
        report.record("start_listening_invoked")
        report.beginCommandAudioRecording()

        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 640))
        buffer.frameLength = 640
        if let channel = buffer.floatChannelData?[0] {
            for index in 0..<Int(buffer.frameLength) {
                channel[index] = sin(Float(index) * 0.07) * 0.05
            }
        }
        let speechRequest = SFSpeechAudioBufferRecognitionRequest()
        let speechSink = VoiceRecognitionRequestSink(speechRequest)
        let oneExistingTap = AppleVoiceAudioCaptureBackend.makeTapHandler { sameBuffer in
            speechSink.append(sameBuffer)
            report.appendCommandAudioBuffer(sameBuffer)
        }
        oneExistingTap(buffer, AVAudioTime())

        report.recordSpeechTranscript("Знайди", isFinal: false)
        report.recordSpeechTranscript("Знайди кав’ярню біля вокзалу", isFinal: false)
        report.recordSpeechTranscript("Знайди кав’ярню біля вокзалу", isFinal: true)
        report.finishCommandAudioRecording(reason: .recognitionFinal)
        report.record("transcript_delivered_to_router", "length=29")
        report.beginHomeRequest(generation: 91)
        report.recordSubmittedInputIfNeeded("Знайди кав’ярню біля вокзалу")
        report.recordNormalizedTranscript("знайти кав’ярню біля вокзалу")
        report.record(
            "canonical_semantic_frame",
            "action=place_search object=cafe location=station constraint_count=1"
        )
        report.record("selected_capability", "capability=placeSearch route=MapKit provider=MapKit")
        report.record("router_accepted", "capability=placeSearch route=MapKit")
        report.recordBoundaryPre("MAPKIT_SEARCH", "mechanism=MKLocalSearch capability=placeSearch")
        report.record("execution_started", "mechanism=MKLocalSearch capability=placeSearch")
        report.recordBoundaryPost("MAPKIT_SEARCH", "mechanism=MKLocalSearch result=success")
        report.record("visible_result", "kind=place_list result=success")
        report.recordTerminal(.success)
        let session = try #require(report.completedSession())

        #expect(session.requestID == requestID)
        #expect(session.events.last?.marker == "request_end")
        #expect(session.events.filter { $0.marker == "terminal_request_state" }.count == 1)
        #expect(session.finalSpeechTranscript == "Знайди кав’ярню біля вокзалу")
        #expect(session.normalizedTranscript == "знайти кав’ярню біля вокзалу")
        let localAudioPath = try #require(session.diagnosticAudioRelativePath)
        let localAudio = root.appendingPathComponent(localAudioPath)
        #expect(FileManager.default.fileExists(atPath: localAudio.path))
        #expect((try localAudio.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0)

        let relaunchedStore = PhysicalDiagnosticLocalStore(rootDirectory: root)
        let durableEvents = relaunchedStore.events(for: requestID, limit: 1_000)
        #expect(!durableEvents.isEmpty)
        #expect(durableEvents.allSatisfy { $0.requestID == requestID })
        #expect(durableEvents.contains { $0.marker == "partial_transcript" && $0.textPayload == "Знайди" })
        #expect(durableEvents.contains {
            $0.marker == "final_transcript" && $0.textPayload == "Знайди кав’ярню біля вокзалу"
        })
        #expect(durableEvents.contains {
            $0.marker == "normalization" && $0.textPayload == "знайти кав’ярню біля вокзалу"
        })
        #expect(durableEvents.last?.marker == "request_end")
        #expect(FileManager.default.fileExists(atPath: localAudio.path))

        let chunkCount = try #require(Int(client.value(for: "ua_trace_chunk_count") ?? ""))
        let encodedTrace = (0..<chunkCount).compactMap {
            client.value(for: String(format: "ua_trace_%02d", $0))
        }.joined()
        let traceData = try #require(Data(base64Encoded: encodedTrace))
        let snapshot = try JSONDecoder().decode(CrashlyticsRequestTraceSnapshot.self, from: traceData)
        let markers = snapshot.events.map(\.marker)

        #expect(snapshot.requestID == requestID)
        #expect(snapshot.generation == 91)
        #expect(snapshot.partialTranscripts == ["Знайди", "Знайди кав’ярню біля вокзалу"])
        #expect(snapshot.finalTranscript == "Знайди кав’ярню біля вокзалу")
        #expect(snapshot.normalizedTranscript == "знайти кав’ярню біля вокзалу")
        #expect(snapshot.audioRelativePath == localAudioPath)
        #expect(markers.contains("canonical_semantic_frame"))
        #expect(markers.contains("selected_capability"))
        #expect(markers.contains("router_accepted"))
        #expect(markers.contains("MAPKIT_SEARCH_PRE"))
        #expect(markers.contains("MAPKIT_SEARCH_POST"))
        #expect(markers.contains("execution_started"))
        #expect(markers.contains("visible_result"))
        #expect(markers.contains("terminal_request_state"))
        #expect(markers.last == "request_end")
        #expect(snapshot.terminalState == DiagnosticTerminalState.success.rawValue)
        #expect(snapshot.result == PhysicalDiagnosticResult.success.rawValue)
        #expect(client.errors.map(\.domain) == ["UA_DIAGNOSTIC_COMMAND_TRACE"])

        var liveAudioExportURL: URL?
        if ProcessInfo.processInfo.environment["UA_FIREBASE_LIVE_E2E"] == "1" {
            let exportURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("ua-firebase-live-\(requestID.uuidString.lowercased()).caf")
            try FileManager.default.copyItem(at: localAudio, to: exportURL)
            liveAudioExportURL = exportURL
        }
        let cloudKit = CloudKitDiagnosticAudioTestDatabase(failSaves: true)
        let audioDelivery = CloudKitDiagnosticAudioDelivery(
            database: cloudKit,
            localStore: relaunchedStore,
            enabled: { true }
        )
        let firstAttempt = Date.now
        await audioDelivery.enqueue(session, now: firstAttempt)

        let firstPendingCount = await audioDelivery.pendingUploads().count
        let firstSavedRecordCount = await cloudKit.savedRecordCount()
        #expect(FileManager.default.fileExists(atPath: localAudio.path))
        #expect(firstPendingCount == 1)
        #expect(firstSavedRecordCount == 0)

        await cloudKit.setFailSaves(false)
        await audioDelivery.flush(now: firstAttempt.addingTimeInterval(3))
        let recordName = "ua-audio-\(requestID.uuidString.lowercased())"
        let audioReadback = try await cloudKit.readBack(recordName: recordName)
        let pendingAfterReadback = await audioDelivery.pendingUploads()
        let receiptRequestIDs = await audioDelivery.verifiedReceipts().map(\.metadata.requestID)
        let saveAttempts = await cloudKit.saveAttempts()
        let savedRecordCount = await cloudKit.savedRecordCount()

        #expect(audioReadback.metadata.requestID == snapshot.requestID)
        #expect(audioReadback.metadata.diagnosticSessionID == session.diagnosticSessionID)
        #expect(audioReadback.downloadedByteCount == audioReadback.metadata.audioByteCount)
        #expect(audioReadback.requestTrace?.requestID == requestID)
        #expect(audioReadback.requestTrace?.finalSpeechTranscript == "Знайди кав’ярню біля вокзалу")
        #expect(audioReadback.requestTrace?.normalizedTranscript == "знайти кав’ярню біля вокзалу")
        #expect(audioReadback.requestTrace?.events.contains { $0.marker == "selected_capability" } == true)
        #expect(audioReadback.requestTrace?.events.contains { $0.marker == "execution_started" } == true)
        #expect(audioReadback.requestTrace?.events.last?.marker == "request_end")
        #expect(audioReadback.downloadedTraceByteCount == audioReadback.metadata.requestTraceByteCount)
        #expect(audioReadback.downloadedTraceSHA256 == audioReadback.metadata.requestTraceSHA256)
        #expect(audioReadback.downloadedSHA256 == audioReadback.metadata.audioSHA256)
        #expect(pendingAfterReadback.isEmpty)
        #expect(receiptRequestIDs == [requestID])
        #expect(!FileManager.default.fileExists(atPath: localAudio.path))
        #expect(saveAttempts == 2)
        #expect(savedRecordCount == 1)

        let pinnedRequestID = UUID()
        let pinnedMetadata = await cloudKit.seed(build: session.build - 4, requestID: pinnedRequestID)
        let obsoleteMetadata = await cloudKit.seed(build: session.build - 3, requestID: UUID())
        let previousTwoMetadata = await cloudKit.seed(build: session.build - 2, requestID: UUID())
        let previousMetadata = await cloudKit.seed(build: session.build - 1, requestID: UUID())
        for metadata in [pinnedMetadata, obsoleteMetadata, previousTwoMetadata, previousMetadata] {
            relaunchedStore.markCloudKitAudioVerified(
                .init(
                    metadata: metadata,
                    audioRelativePath: "audio/\(metadata.requestID.uuidString.lowercased()).caf",
                    attempts: 0,
                    nextAttemptAt: firstAttempt,
                    state: .uploadedAwaitingVerification,
                    lastErrorCategory: nil
                ),
                verifiedAt: firstAttempt
            )
        }
        try await audioDelivery.setPinned(requestID: pinnedRequestID, pinned: true)
        await cloudKit.setFailMetadataReads(true)
        await audioDelivery.flush(now: firstAttempt.addingTimeInterval(4))
        await cloudKit.setFailMetadataReads(false)

        let retained = try await cloudKit.allMetadata()
        let retainedReceipts = relaunchedStore.cloudKitAudioReceipts()
        let retainedBuilds = Set([session.build - 4, session.build - 2, session.build - 1, session.build])
        #expect(Set(retained.map(\.physicalBuild)) == retainedBuilds)
        #expect(Set(retainedReceipts.map { $0.metadata.physicalBuild }) == retainedBuilds)
        #expect(retained.first(where: { $0.requestID == pinnedRequestID })?.pinned == true)
        #expect(retainedReceipts.first(where: { $0.metadata.requestID == pinnedRequestID })?.metadata.pinned == true)

        if ProcessInfo.processInfo.environment["UA_FIREBASE_LIVE_E2E"] == "1" {
            if FirebaseApp.app() == nil { FirebaseApp.configure() }
            CrashlyticsDiagnosticBridge.configureTargetedValidationCollection()
            let liveBridge = CrashlyticsDiagnosticBridge()
            let liveIdentity = CrashlyticsDiagnosticRequestIdentity(
                diagnosticSessionID: session.diagnosticSessionID ?? session.sessionID,
                requestID: requestID,
                generation: session.requestGeneration ?? 0,
                appVersion: session.appVersion,
                build: session.build
            )
            liveBridge.beginRequest(liveIdentity, inputMode: "voice")
            liveBridge.recordTerminal(session)
            Crashlytics.crashlytics().sendUnsentReports()
            print("UA_FIREBASE_E2E_REQUEST_ID=\(requestID.uuidString)")
            print("UA_FIREBASE_E2E_AUDIO_PATH=\(liveAudioExportURL?.path ?? "missing")")
            try await Task.sleep(for: .seconds(8))
        }
    }

    private func makeSession(
        diagnosticSessionID: UUID,
        requestID: UUID,
        generation: UInt64,
        terminalState: DiagnosticTerminalState,
        detailed: Bool
    ) -> PhysicalDiagnosticSession {
        var session = PhysicalDiagnosticSession(
            schema: 2,
            sessionID: requestID,
            liveTestID: "FIREBASE-SIDE-CAR-TEST",
            feature: "voice",
            appVersion: "0.1.0",
            build: 32,
            environment: "test",
            osVersion: "26.0",
            deviceClass: "test",
            startedAt: Date(timeIntervalSince1970: 1),
            endedAt: Date(timeIntervalSince1970: 2),
            durationMilliseconds: 1_000,
            result: terminalState == .success ? .success : .failure,
            failureStage: terminalState == .success ? nil : "provider",
            errorDomain: nil,
            errorCode: nil,
            events: []
        )
        session.diagnosticSessionID = diagnosticSessionID
        session.requestID = requestID
        session.requestGeneration = generation
        session.terminalState = terminalState
        session.detailedDiagnosticsConsent = detailed
        return session
    }
}

private final class RecordingCrashlyticsClient: CrashlyticsClient, @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [String: String] = [:]
    private var storedLogs: [String] = []
    private var storedErrors: [NSError] = []

    var values: [String: String] { lock.withLock { storedValues } }
    var logs: [String] { lock.withLock { storedLogs } }
    var errors: [NSError] { lock.withLock { storedErrors } }

    func value(for key: String) -> String? { lock.withLock { storedValues[key] } }

    func setCustomValue(_ value: Any, forKey key: String) {
        lock.withLock { storedValues[key] = String(describing: value) }
    }

    func log(_ message: String) {
        lock.withLock { storedLogs.append(message) }
    }

    func record(error: Error) {
        lock.withLock { storedErrors.append(error as NSError) }
    }
}

private final class RecordingDiagnosticRecorder: CrashlyticsDiagnosticRecording, @unchecked Sendable {
    struct Begin { let identity: CrashlyticsDiagnosticRequestIdentity; let inputMode: String }
    struct Event { let marker: String; let sequence: Int; let identity: CrashlyticsDiagnosticRequestIdentity }
    struct Transcript { let text: String; let normalized: Bool; let detailed: Bool }

    private let lock = NSLock()
    private var storedBegins: [Begin] = []
    private var storedEvents: [Event] = []
    private var storedTranscripts: [Transcript] = []
    private var storedTerminals: [PhysicalDiagnosticSession] = []

    var begins: [Begin] { lock.withLock { storedBegins } }
    var events: [Event] { lock.withLock { storedEvents } }
    var transcripts: [Transcript] { lock.withLock { storedTranscripts } }
    var terminals: [PhysicalDiagnosticSession] { lock.withLock { storedTerminals } }

    func beginRequest(_ identity: CrashlyticsDiagnosticRequestIdentity, inputMode: String) {
        lock.withLock { storedBegins.append(.init(identity: identity, inputMode: inputMode)) }
    }

    func recordEvent(
        _ marker: String,
        details: String,
        sequence: Int,
        identity: CrashlyticsDiagnosticRequestIdentity
    ) {
        lock.withLock { storedEvents.append(.init(marker: marker, sequence: sequence, identity: identity)) }
    }
    func recordPartialTranscript(
        _ transcript: String,
        sequence: Int,
        identity: CrashlyticsDiagnosticRequestIdentity,
        detailedDiagnosticsEnabled: Bool
    ) {
        lock.withLock {
            storedTranscripts.append(.init(text: transcript, normalized: false, detailed: detailedDiagnosticsEnabled))
        }
    }

    func recordTranscript(
        _ transcript: String,
        normalized: Bool,
        sequence: Int,
        identity: CrashlyticsDiagnosticRequestIdentity,
        detailedDiagnosticsEnabled: Bool
    ) {
        lock.withLock {
            storedTranscripts.append(.init(text: transcript, normalized: normalized, detailed: detailedDiagnosticsEnabled))
        }
    }

    func recordTerminal(_ session: PhysicalDiagnosticSession) {
        lock.withLock { storedTerminals.append(session) }
    }

    func recordRecoveredUncleanSession(_ session: PhysicalDiagnosticSession) {}
    func recordMetricKitPayload(
        kind: String,
        fingerprint: String,
        payload: String,
        identity: CrashlyticsDiagnosticRequestIdentity
    ) {}
}
