import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Physical diagnostic delivery", .serialized)
struct PhysicalDiagnosticDeliveryTests {
    @Test func productionUploadIsFailClosedOutsideInternalTestFlight() async {
        let suite = UserDefaults(suiteName: UUID().uuidString)!
        let delivery = PhysicalDiagnosticDelivery(attest: UnsupportedAttest(), transport: FailingTransport(), defaults: suite, enabled: { false })
        await delivery.enqueue(sampleSession())
        #expect(await delivery.state == .queued)
        #expect(await delivery.pendingCount() == 0)
    }

    @Test func offlineRetryIsBoundedAndDuplicateSessionIsDeduplicated() async {
        let suite = UserDefaults(suiteName: UUID().uuidString)!
        let delivery = PhysicalDiagnosticDelivery(attest: SupportedAttest(), transport: FailingTransport(), defaults: suite, enabled: { true })
        let session = sampleSession()
        await delivery.enqueue(session)
        #expect(await delivery.pendingCount() == 1)
        #expect(await delivery.pendingAttempts() == [1])
        await delivery.enqueue(session)
        #expect(await delivery.pendingCount() == 1)
        #expect(await delivery.pendingAttempts() == [2])
        await delivery.flush()
        #expect(await delivery.pendingCount() == 0)
        #expect(await delivery.state == .expired)
    }

    @Test @MainActor func earlyStopWithoutTranscriptStillProducesPrivacySafeSession() {
        let report = LocalVoiceDiagnosticReport.shared
        report.reset()
        report.record("start_listening_invoked")
        report.record("recognizer_ready", "locale=uk_UA available=true")
        report.record("stop_invoked", "reason=routeChange")
        report.record("state_transition", "state=idle")
        let session = report.completedSession()
        #expect(session != nil)
        #expect(session?.events.contains(where: { $0.marker == "stop_invoked" }) == true)
        #expect(session?.events.flatMap(\.attributes.values).contains(where: { $0.contains("spoken private text") }) == false)
    }

    @Test @MainActor func successfulVoiceChainIsNotMisclassifiedByNoErrorCallbackMetadata() {
        let report = LocalVoiceDiagnosticReport.shared
        report.reset()
        report.record("start_listening_invoked")
        report.record("recognition_callback", "error_domain=none error_code=0 final=true")
        report.record("router_received")
        report.record("router_accepted")
        report.record("execution_started")
        report.record("visible_result")
        report.record("state_transition", "state=idle")
        let session = report.completedSession()
        #expect(session?.result == .success)
        #expect(session?.failureStage == nil)
        #expect(session?.errorDomain == nil)
        #expect(session?.errorCode == nil)
    }

    @Test @MainActor func realRecognitionErrorRemainsFailure() {
        let report = LocalVoiceDiagnosticReport.shared
        report.reset()
        report.record("start_listening_invoked")
        report.record("recognition_callback", "error_domain=kAFAssistantErrorDomain error_code=1110 final=false")
        report.record("state_transition", "state=idle")
        let session = report.completedSession()
        #expect(session?.result == .failure)
        #expect(session?.failureStage == "recognition_callback")
        #expect(session?.errorDomain == "kAFAssistantErrorDomain")
        #expect(session?.errorCode == 1110)
    }

    @Test @MainActor func weatherMarkersAfterIdleStillProduceSession() {
        let report = LocalVoiceDiagnosticReport.shared; report.reset()
        report.record("start_listening_invoked")
        report.record("state_transition", "state=idle")
        report.record("state_delivered_to_view_model", "state=idle")
        report.record("weather_location_resolution_started")
        report.record("weather_location_resolution_succeeded", "status=success")
        report.record("weatherkit_request_failed", "error_domain=WeatherService error_code=2 error_type=WeatherError")
        report.record("weather_context_failed", "error_domain=WeatherService error_code=2 error_type=WeatherError")
        let session = report.completedSession()
        #expect(session != nil)
        #expect(session?.failureStage == "weather_context_failed")
        #expect(session?.errorCode == 2)
        #expect(session?.events.contains(where: { event in event.marker == "weatherkit_request_failed" }) == true)
    }

    @Test func diagnosticReportUploadsMetadataNotTranscriptOrAudio() throws {
        let data = try JSONEncoder.diagnostic.encode(sampleSession())
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("spoken words")); #expect(!text.contains("rawAudio"))
        #expect(text.contains("MS-800-LIVE-VOICE-QA")); #expect(text.contains("recognition_callback"))
    }

    @Test func appAttestBootstrapFailureReportsExactSafeStageWithoutKeyMaterial() async {
        let suite = UserDefaults(suiteName: UUID().uuidString)!
        let transport = RecordingBootstrapTransport()
        let delivery = PhysicalDiagnosticDelivery(attest: FailingGenerateKeyAttest(), transport: transport, defaults: suite, enabled: { true })
        await delivery.enqueue(sampleSession())
        let report = transport.bootstrapReport
        #expect(report?.contains("generate_key_invoked") == true)
        #expect(report?.contains("DCErrorDomain") == true)
        #expect(report?.contains("spoken words") == false)
        #expect(report?.contains("private-key") == false)
    }

    @Test func serverResponseUsesISO8601WithoutChangingLocalQueueDateCoding() throws {
        struct Dated: Codable, Equatable { let date: Date }
        let iso = Data(#"{"date":"2026-09-05T00:21:22Z"}"#.utf8)
        #expect(try JSONDecoder.serverDiagnosticResponse.decode(Dated.self, from: iso).date == Date(timeIntervalSince1970: 1_788_567_682))
        let local = Dated(date: Date(timeIntervalSinceReferenceDate: 123))
        #expect(try JSONDecoder.diagnostic.decode(Dated.self, from: JSONEncoder.diagnostic.encode(local)) == local)
    }

    @Test @MainActor func incompleteTypedRequestIsRecoveredOnceWithoutPersonalContent() {
        let suiteName = UUID().uuidString
        let suite = UserDefaults(suiteName: suiteName)!
        let key = "test-active-request"
        suite.removeObject(forKey: key)
        let beforeCrash = LocalVoiceDiagnosticReport(defaults: suite, persistenceKey: key)
        beforeCrash.beginHomeRequest()
        beforeCrash.record("router_received", "capability=contact_call contact=private-name")
        let afterRestart = LocalVoiceDiagnosticReport(defaults: suite, persistenceKey: key)
        let recovered = afterRestart.recoveredIncompleteSession()
        #expect(recovered?.result == .failure)
        #expect(recovered?.failureStage == "router_received")
        #expect(recovered?.errorDomain == "ProcessTerminatedBeforeTerminalResult")
        #expect(recovered?.events.allSatisfy { $0.attributes.isEmpty } == true)
        #expect(afterRestart.recoveredIncompleteSession() == nil)
    }

    @Test @MainActor func terminalTypedRequestClearsCrashJournal() {
        let suiteName = UUID().uuidString
        let suite = UserDefaults(suiteName: suiteName)!
        let key = "test-terminal-request"
        suite.removeObject(forKey: key)
        let report = LocalVoiceDiagnosticReport(defaults: suite, persistenceKey: key)
        report.beginHomeRequest()
        report.record("visible_result", "kind=deterministic")
        #expect(report.completedSession()?.result == .success)
        #expect(LocalVoiceDiagnosticReport(defaults: suite, persistenceKey: key).recoveredIncompleteSession() == nil)
    }

    private func sampleSession() -> PhysicalDiagnosticSession {
        .init(schema: 1, sessionID: UUID(), liveTestID: "MS-800-LIVE-VOICE-QA", feature: "voice", appVersion: "0.1.0", build: 10,
              environment: "internal-testflight", osVersion: "26.6.1", deviceClass: "iPhone", startedAt: .now, endedAt: .now,
              durationMilliseconds: 1, result: .failure, failureStage: "recognition_callback", errorDomain: "test", errorCode: 1,
              events: [.init(sequence: 1, timestamp: .now, marker: "recognition_callback", attributes: ["error_code": "1"])])
    }
}

private struct UnsupportedAttest: AppAttestServicing {
    let isSupported = false
    func generateKey() async throws -> String { throw PhysicalDiagnosticDeliveryError.unsupported }
    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data { throw PhysicalDiagnosticDeliveryError.unsupported }
    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data { throw PhysicalDiagnosticDeliveryError.unsupported }
}
private struct SupportedAttest: AppAttestServicing {
    let isSupported = true
    func generateKey() async throws -> String { "test-key" }
    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data { Data() }
    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data { Data() }
}
private struct FailingTransport: DiagnosticHTTPTransport {
    func post<Request, Response>(_ path: String, body: Request, response: Response.Type) async throws -> Response where Request : Encodable, Response : Decodable {
        throw PhysicalDiagnosticDeliveryError.httpFailure(statusCode: 503)
    }
}
private struct FailingGenerateKeyAttest: AppAttestServicing {
    let isSupported = true
    func generateKey() async throws -> String { throw NSError(domain: "DCErrorDomain", code: 2) }
    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data { Data() }
    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data { Data() }
}
private final class RecordingBootstrapTransport: DiagnosticHTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var storedReport: String?
    var bootstrapReport: String? { lock.withLock { storedReport } }
    func post<Request, Response>(_ path: String, body: Request, response: Response.Type) async throws -> Response where Request: Encodable, Response: Decodable {
        guard path == "v1/app-attest/bootstrap-failure" else { throw PhysicalDiagnosticDeliveryError.httpFailure(statusCode: 503) }
        let report = String(data: try JSONEncoder.diagnostic.encode(body), encoding: .utf8)
        lock.withLock { storedReport = report }
        throw PhysicalDiagnosticDeliveryError.httpFailure(statusCode: 503)
    }
}
