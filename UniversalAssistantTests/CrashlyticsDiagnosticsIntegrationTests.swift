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
        #expect(client.value(for: "ua_transcript") == nil)
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
        let terminalEventIsLast = eventMarkers.last == "terminal_request_state"
        let allEventsOwned = recorder.events.allSatisfy { $0.identity.requestID == session.requestID }
        let terminalRequestIDsMatch = recorder.terminals.map(\.requestID) == [session.requestID]
        #expect(transcriptsAreDetailed)
        #expect(hasSemanticFrame)
        #expect(hasSelectedCapability)
        #expect(hasMapKitPre)
        #expect(hasMapKitPost)
        #expect(terminalEventIsLast)
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
