import Foundation
import Testing
@testable import UniversalAssistantServer

@Suite("Physical diagnostics security and retention", .serialized)
struct PhysicalDiagnosticsTests {
    @Test func challengeIsOneTimeOperationBoundAndExpires() async throws {
        let store = ChallengeStore(lifetime: 5)
        let now = Date(timeIntervalSince1970: 1_000)
        let issued = try await store.issue(operation: "diagnostic", now: now)
        _ = try await store.consume(id: issued.0, operation: "diagnostic", now: now)
        await #expect(throws: DiagnosticServerError.self) { try await store.consume(id: issued.0, operation: "diagnostic", now: now) }
        let expired = try await store.issue(operation: "attest", now: now)
        await #expect(throws: DiagnosticServerError.self) { try await store.consume(id: expired.0, operation: "attest", now: now.addingTimeInterval(6)) }
    }

    @Test func groqChallengesAreExplicitlyAllowlistedAndOperationBound() async throws {
        let store = ChallengeStore(lifetime: 5)
        let now = Date(timeIntervalSince1970: 1_000)
        let transcription = try await store.issue(operation: "groq-transcription", now: now)
        await #expect(throws: DiagnosticServerError.self) {
            try await store.consume(id: transcription.0, operation: "groq-semantic", now: now)
        }
        let semantic = try await store.issue(operation: "groq-semantic", now: now)
        _ = try await store.consume(id: semantic.0, operation: "groq-semantic", now: now)
        await #expect(throws: DiagnosticServerError.self) {
            _ = try await store.issue(operation: "arbitrary-ai-operation", now: now)
        }
    }

    @Test func storeDeduplicatesAndRejectsForbiddenOrUnknownSchema() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try DiagnosticSessionStore(directory: root, retention: 60, maximumRecords: 2)
        let session = sample()
        #expect(try await store.put(session))
        #expect(try await !store.put(session))
        let invalid = PhysicalDiagnosticSession(schema: 2, sessionID: UUID(), liveTestID: session.liveTestID, feature: session.feature,
            appVersion: session.appVersion, build: session.build, environment: session.environment, osVersion: session.osVersion,
            deviceClass: session.deviceClass, startedAt: session.startedAt, endedAt: session.endedAt, durationMilliseconds: 1,
            result: .failure, failureStage: nil, errorDomain: nil, errorCode: nil, events: session.events)
        await #expect(throws: DiagnosticServerError.self) { _ = try await store.put(invalid) }
        let forbidden = PhysicalDiagnosticSession(schema: 1, sessionID: UUID(), liveTestID: session.liveTestID, feature: session.feature,
            appVersion: session.appVersion, build: session.build, environment: session.environment, osVersion: session.osVersion,
            deviceClass: session.deviceClass, startedAt: session.startedAt, endedAt: session.endedAt, durationMilliseconds: 1,
            result: .failure, failureStage: nil, errorDomain: nil, errorCode: nil,
            events: [.init(sequence: 1, timestamp: session.startedAt, marker: "recognition_callback", attributes: ["transcript_text": "forbidden"])])
        await #expect(throws: DiagnosticServerError.self) { _ = try await store.put(forbidden) }
    }

    @Test func currentHomeLifecycleAndRecoveredCrashMarkersShareTheProductionContract() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try DiagnosticSessionStore(directory: root, retention: 60, maximumRecords: 4)
        let now = Date(timeIntervalSince1970: 1_000)
        let lifecycle = [
            "home_request_started", "stale_start_suppressed", "stale_stop_suppressed",
            "stale_recognition_suppressed", "audio_capture_stop", "scene_transition",
            "confirmation_resolved", "visible_result"
        ].enumerated().map { index, marker in
            DiagnosticEvent(sequence: index + 1, timestamp: now, marker: marker, attributes: [:])
        }
        let voice = PhysicalDiagnosticSession(
            schema: 1, sessionID: UUID(), liveTestID: "MS-800-LIVE-VOICE-QA", feature: "voice",
            appVersion: "0.1.0", build: 30, environment: "internal-testflight", osVersion: "26.6.1",
            deviceClass: "iPhone", startedAt: now, endedAt: now, durationMilliseconds: 0,
            result: .success, failureStage: nil, errorDomain: nil, errorCode: nil, events: lifecycle
        )
        #expect(try await store.put(voice))

        let recovered = PhysicalDiagnosticSession(
            schema: 1, sessionID: UUID(), liveTestID: "MS-800-RECOVERED-REQUEST", feature: "request",
            appVersion: "0.1.0", build: 30, environment: "internal-testflight", osVersion: "26.6.1",
            deviceClass: "iPhone", startedAt: now, endedAt: now, durationMilliseconds: 0,
            result: .crashSuspected, failureStage: "router_received", errorDomain: "ProcessTerminatedBeforeTerminalResult",
            errorCode: -1, events: [.init(sequence: 1, timestamp: now, marker: "router_received", attributes: [:])]
        )
        #expect(try await store.put(recovered))
    }

    @Test func assertionCounterMustAdvance() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try AppAttestRegistrationStore(directory: root)
        try await store.register(.init(keyID: "key", publicKey: Data([1]), counter: 0, environment: "production", registeredAt: .now))
        try await store.advanceCounter(keyID: "key", to: 1)
        await #expect(throws: DiagnosticServerError.self) { try await store.advanceCounter(keyID: "key", to: 1) }
    }

    @Test func registrationAndCounterSurviveServerRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try AppAttestRegistrationStore(directory: root)
        let registeredAt = Date(timeIntervalSince1970: 1_000)
        try await first.register(.init(keyID: "key", publicKey: Data([1, 2, 3]), counter: 4, environment: "production", registeredAt: registeredAt))
        try await first.advanceCounter(keyID: "key", to: 5)

        let restarted = try AppAttestRegistrationStore(directory: root)
        let record = await restarted.record(for: "key")
        #expect(record?.publicKey == Data([1, 2, 3]))
        #expect(record?.counter == 5)
        #expect(record?.environment == "production")
        #expect(record?.registeredAt == registeredAt)
        try await restarted.advanceCounter(keyID: "key", to: 6)
    }

    @Test func bootstrapStoreAcceptsOnlyBoundedAllowlistedFailureMetadata() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try AppAttestBootstrapFailureStore(directory: root, retention: 60, maximumRecords: 2)
        let now = Date(timeIntervalSince1970: 1_000)
        let valid = AppAttestBootstrapFailureReport(schema: 1, reportID: UUID(), appVersion: "0.1.0", build: 12,
            environment: "internal-testflight", osVersion: "26.6.1", deviceClass: "iPhone", startedAt: now, endedAt: now,
            failureStage: "attest_key_invoked", errorDomain: "DCErrorDomain", errorCode: 2,
            events: [.init(sequence: 1, marker: "bootstrap_failed", attributes: ["stage": "attest_key_invoked", "error_code": "2"])])
        #expect(try await store.put(valid))
        #expect(try await !store.put(valid))
        let forbidden = AppAttestBootstrapFailureReport(schema: 1, reportID: UUID(), appVersion: "0.1.0", build: 12,
            environment: "internal-testflight", osVersion: "26.6.1", deviceClass: "iPhone", startedAt: now, endedAt: now,
            failureStage: "attest_key_invoked", errorDomain: "DCErrorDomain", errorCode: 2,
            events: [.init(sequence: 1, marker: "bootstrap_failed", attributes: ["transcript": "forbidden"])])
        await #expect(throws: DiagnosticServerError.self) { _ = try await store.put(forbidden) }
        let validData = try JSONEncoder.canonical.encode(valid)
        try AppAttestBootstrapFailureStore.validateRawSchema(validData)
        let clientTransportData = try JSONEncoder().encode(valid)
        #expect(try AppAttestBootstrapFailureStore.decodeTransport(clientTransportData) == valid)
        var object = try #require(JSONSerialization.jsonObject(with: validData) as? [String: Any])
        object["arbitrary"] = "rejected"
        let unknownFieldData = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DiagnosticServerError.self) { try AppAttestBootstrapFailureStore.validateRawSchema(unknownFieldData) }
    }

    private func sample() -> PhysicalDiagnosticSession {
        let now = Date(timeIntervalSince1970: 1_000)
        return .init(schema: 1, sessionID: UUID(), liveTestID: "MS-800-LIVE-VOICE-QA", feature: "voice", appVersion: "0.1.0",
                     build: 10, environment: "internal-testflight", osVersion: "26.6.1", deviceClass: "iPhone",
                     startedAt: now, endedAt: now.addingTimeInterval(1), durationMilliseconds: 1_000, result: .failure,
                     failureStage: "recognition_callback", errorDomain: "test", errorCode: 1,
                     events: [.init(sequence: 1, timestamp: now, marker: "recognition_callback", attributes: ["error_code": "1"])])
    }
}
