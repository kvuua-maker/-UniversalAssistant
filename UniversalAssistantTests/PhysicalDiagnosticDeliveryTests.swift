import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Physical diagnostic delivery", .serialized)
struct PhysicalDiagnosticDeliveryTests {
    @Test func localBlackBoxPersistsWhileNetworkUploadIsFailClosedOutsideInternalTestFlight() async {
        let suite = UserDefaults(suiteName: UUID().uuidString)!
        let store = makeStore()
        let delivery = PhysicalDiagnosticDelivery(attest: UnsupportedAttest(), transport: FailingTransport(), defaults: suite, localStore: store, enabled: { false })
        await delivery.enqueue(sampleSession())
        #expect(await delivery.state == .queued)
        #expect(await delivery.pendingCount() == 1)
        #expect(store.deliveryStatus() == .pendingUpload)
    }

    @Test func offlineRetryPreservesEventWithBoundedBackoffAndDeduplicates() async {
        let suite = UserDefaults(suiteName: UUID().uuidString)!
        let store = makeStore()
        let delivery = PhysicalDiagnosticDelivery(attest: SupportedAttest(), transport: FailingTransport(), defaults: suite, localStore: store, enabled: { true })
        let session = sampleSession()
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        await delivery.enqueue(session, now: now)
        #expect(await delivery.pendingCount(now: now) == 1)
        #expect(await delivery.pendingAttempts(now: now) == [1])
        await delivery.enqueue(session, now: now)
        #expect(await delivery.pendingCount(now: now) == 1)
        #expect(await delivery.pendingAttempts(now: now) == [1])
        await delivery.flush(now: now.addingTimeInterval(3))
        #expect(await delivery.pendingCount(now: now.addingTimeInterval(3)) == 1)
        #expect(await delivery.pendingAttempts(now: now.addingTimeInterval(3)) == [2])
        #expect(await delivery.state == .failedRetryable)
        #expect(store.deliveryStatus() == .retrying)
    }

    @Test @MainActor func earlyStopWithoutTranscriptStillProducesPrivacySafeSession() {
        let report = LocalVoiceDiagnosticReport(localStore: makeStore())
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
        let report = LocalVoiceDiagnosticReport(localStore: makeStore())
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
        let report = LocalVoiceDiagnosticReport(localStore: makeStore())
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
        let report = LocalVoiceDiagnosticReport(localStore: makeStore()); report.reset()
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
        let delivery = PhysicalDiagnosticDelivery(attest: FailingGenerateKeyAttest(), transport: transport, defaults: suite, localStore: makeStore(), enabled: { true })
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
        let store = makeStore()
        let beforeCrash = LocalVoiceDiagnosticReport(defaults: suite, persistenceKey: key, localStore: store)
        beforeCrash.beginHomeRequest()
        beforeCrash.record("router_received", "capability=contact_call contact=private-name")
        #expect(store.recentEvents().flatMap(\.attributes.values).contains("private-name") == false)
        let afterRestart = LocalVoiceDiagnosticReport(defaults: suite, persistenceKey: key, localStore: store)
        let recovered = afterRestart.recoveredIncompleteSession()
        #expect(recovered?.result == .crashSuspected)
        #expect(recovered?.failureStage == "router_received")
        #expect(recovered?.errorDomain == "ProcessTerminatedBeforeTerminalResult")
        #expect(recovered?.anomaly?.certainty == .probableFailureBoundary)
        #expect(recovered?.events.flatMap(\.attributes.values).contains("private-name") == false)
        #expect(afterRestart.recoveredIncompleteSession() == nil)
    }

    @Test @MainActor func terminalTypedRequestClearsCrashJournal() {
        let suiteName = UUID().uuidString
        let suite = UserDefaults(suiteName: suiteName)!
        let key = "test-terminal-request"
        suite.removeObject(forKey: key)
        let store = makeStore()
        let report = LocalVoiceDiagnosticReport(defaults: suite, persistenceKey: key, localStore: store)
        report.beginHomeRequest()
        report.record("visible_result", "kind=deterministic")
        #expect(report.completedSession()?.result == .success)
        #expect(LocalVoiceDiagnosticReport(defaults: suite, persistenceKey: key, localStore: store).recoveredIncompleteSession() == nil)
    }

    @Test @MainActor func busyRequestIsBoundedWithoutDroppingIngressOrTerminalEvidence() {
        let suiteName = UUID().uuidString
        let suite = UserDefaults(suiteName: suiteName)!
        let report = LocalVoiceDiagnosticReport(defaults: suite, persistenceKey: "bounded-report", localStore: makeStore())
        report.reset()
        report.beginHomeRequest()
        for _ in 0..<300 { report.record("recognition_callback") }
        report.record("visible_result")
        let session = report.completedSession()
        #expect(session?.events.count == 250)
        #expect(session?.events.first?.marker == "request_created")
        #expect(session?.events.last?.marker == "request_end")
        #expect(session?.events.contains(where: { $0.marker == "terminal_request_state" }) == true)
        #expect(session?.events.enumerated().allSatisfy { $0.offset + 1 == $0.element.sequence } == true)
    }

    @Test func durableSnapshotAndOrderedTraceSurviveStoreRecreation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ua-diagnostics-relaunch-\(UUID().uuidString)", isDirectory: true)
        let first = PhysicalDiagnosticLocalStore(rootDirectory: root)
        let requestID = UUID()
        let snapshot = DiagnosticActiveRequestSnapshot(
            diagnosticSessionID: UUID(), requestID: requestID, requestGeneration: 7, build: 32,
            eventSequence: 0, lastStage: "REQUEST_CREATED", lastPRE: nil, lastPOST: nil,
            selectedCapability: nil, terminal: false, terminalState: nil, updatedAt: .now
        )
        first.begin(snapshot)
        first.append(.init(sequence: 1, timestamp: .now, marker: "request_created", attributes: ["source": "home"]), durable: true)
        first.updateActive(sequence: 1, stage: "request_created", capability: "contactLookup")

        let afterRelaunch = PhysicalDiagnosticLocalStore(rootDirectory: root)
        #expect(afterRelaunch.activeSnapshot()?.requestID == requestID)
        #expect(afterRelaunch.activeSnapshot()?.requestGeneration == 7)
        #expect(afterRelaunch.activeSnapshot()?.selectedCapability == "contactLookup")
        #expect(afterRelaunch.recentEvents().map(\.marker) == ["request_created"])
    }

    @Test func diagnosticsStatusRetainsLastCompletedRequestAndCountsUploadedEvents() {
        let store = makeStore()
        let diagnosticSessionID = UUID()
        let requestID = UUID()
        var event = PhysicalDiagnosticEvent(
            sequence: 1, timestamp: .now, marker: "terminal_request_state",
            attributes: ["state": DiagnosticTerminalState.success.rawValue]
        )
        event.diagnosticSessionID = diagnosticSessionID
        event.requestID = requestID
        event.requestGeneration = 7
        event.build = 32
        store.append(event, durable: true)
        store.addReceipt(.init(sessionID: requestID, uploadedAt: .now, eventCount: 9))

        let status = store.status()
        #expect(status.diagnosticSessionID == diagnosticSessionID)
        #expect(status.lastRequestID == requestID)
        #expect(status.lastStage == "terminal_request_state")
        #expect(status.uploadedEvents == 9)
    }

    @Test @MainActor func preWithoutPostProducesOnlyProbableFailureBoundary() {
        let store = makeStore()
        let report = LocalVoiceDiagnosticReport(localStore: store)
        report.beginHomeRequest(generation: 11)
        report.recordBoundaryPre("CONTACT_FETCH", "capability=contactLookup")

        let recovered = report.recoveredIncompleteSession()
        #expect(recovered?.result == .crashSuspected)
        #expect(recovered?.failureStage == "CONTACT_FETCH_PRE")
        #expect(recovered?.anomaly?.certainty == .probableFailureBoundary)
        #expect(recovered?.anomaly?.reason == "missing_expected_post:CONTACT_FETCH_POST")
        #expect(recovered?.anomaly?.certainty != .confirmedRootCause)
    }

    @Test @MainActor func recoveredUncleanRequestUploadsTheDurablePreCrashTrace() {
        let store = makeStore()
        let beforeCrash = LocalVoiceDiagnosticReport(
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            localStore: store
        )
        beforeCrash.beginHomeRequest(generation: 41)
        beforeCrash.record("normalization", "length=24")
        beforeCrash.record("selected_capability", "capability=contactLookup")
        beforeCrash.recordBoundaryPre("CONTACT_FETCH", "kind=identifier")

        let recovered = LocalVoiceDiagnosticReport(
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            localStore: store
        ).recoveredIncompleteSession()
        let markers = recovered?.events.map(\.marker) ?? []
        #expect(markers.contains("request_created"))
        #expect(markers.contains("normalization"))
        #expect(markers.contains("selected_capability"))
        #expect(markers.contains("CONTACT_FETCH_PRE"))
        #expect(markers.last == "request_end")
        #expect(markers.contains("unclean_termination_detected"))
        #expect(recovered?.events.enumerated().allSatisfy { $0.offset + 1 == $0.element.sequence } == true)
        #expect(recovered?.anomaly?.reason == "missing_expected_post:CONTACT_FETCH_POST")
    }

    @Test func completedNestedBoundaryBecomesTheLastCoherentDurablePair() {
        let store = makeStore()
        store.begin(.init(
            diagnosticSessionID: UUID(), requestID: UUID(), requestGeneration: 6, build: 32,
            eventSequence: 0, lastStage: "request_created", lastPRE: nil, lastPOST: nil,
            selectedCapability: nil, terminal: false, terminalState: nil, updatedAt: .now
        ))
        store.updateActive(sequence: 1, stage: "EXECUTOR_PRE", pre: "EXECUTOR_PRE")
        store.updateActive(sequence: 2, stage: "CONTACT_FETCH_PRE", pre: "CONTACT_FETCH_PRE")
        store.updateActive(sequence: 3, stage: "CONTACT_FETCH_POST", post: "CONTACT_FETCH_POST")
        store.updateActive(sequence: 4, stage: "EXECUTOR_POST", post: "EXECUTOR_POST")
        #expect(store.activeSnapshot()?.lastPRE == "EXECUTOR_PRE")
        #expect(store.activeSnapshot()?.lastPOST == "EXECUTOR_POST")
        #expect(DiagnosticAnomalyAnalyzer.analyze(events: [], active: store.activeSnapshot())?.reason == "request_not_terminal")
    }

    @Test @MainActor func ambientLifecycleMarkerDoesNotManufactureAnActiveRequest() {
        let store = makeStore()
        let report = LocalVoiceDiagnosticReport(
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            localStore: store
        )
        report.record("scene_transition", "state=background")
        #expect(store.activeSnapshot() == nil)
        #expect(store.recentEvents().isEmpty)
        #expect(report.recoveredIncompleteSession() == nil)
    }

    @Test @MainActor func perEventIdentityAndConsentTranscriptSurviveUncleanRelaunch() throws {
        let store = makeStore()
        let report = LocalVoiceDiagnosticReport(
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            persistenceKey: "identity-transcript",
            localStore: store
        )
        report.detailedDiagnosticsEnabled = true
        report.beginHomeRequest(generation: 73)
        report.recordSpeechTranscript("Знайди нечітко розпізнаний бренд", isFinal: true)
        report.recordNormalizedTranscript("знайди нечітко розпізнаний бренд")
        report.recordBoundaryPre("CONTACT_RESOLUTION")

        let snapshot = try #require(store.activeSnapshot())
        let durableEvents = store.recentEvents()
        #expect(!durableEvents.isEmpty)
        #expect(durableEvents.allSatisfy { $0.diagnosticSessionID == snapshot.diagnosticSessionID })
        #expect(durableEvents.allSatisfy { $0.requestID == snapshot.requestID })
        #expect(durableEvents.allSatisfy { $0.requestGeneration == 73 })
        #expect(durableEvents.allSatisfy { $0.build != nil })
        #expect(snapshot.finalSpeechTranscript == "Знайди нечітко розпізнаний бренд")
        #expect(snapshot.normalizedTranscript == "знайди нечітко розпізнаний бренд")

        let recovered = try #require(report.recoveredIncompleteSession())
        #expect(recovered.finalSpeechTranscript == snapshot.finalSpeechTranscript)
        #expect(recovered.normalizedTranscript == snapshot.normalizedTranscript)
        #expect(recovered.events.first?.requestID == snapshot.requestID)
        #expect(recovered.events.first?.requestGeneration == 73)
        #expect(recovered.anomaly?.reason == "missing_expected_post:CONTACT_RESOLUTION_POST")
    }

    @Test @MainActor func detailedTranscriptConsentCapturesNormalizedTextWithPrivacyRedaction() {
        let report = LocalVoiceDiagnosticReport(defaults: UserDefaults(suiteName: UUID().uuidString)!, localStore: makeStore())
        report.detailedDiagnosticsEnabled = true
        report.beginHomeRequest(generation: 9)
        report.recordSpeechTranscript("Відкрий https://private.example/a і подзвони +380 67 123 45 67", isFinal: true)
        report.recordNormalizedTranscript("відкрий https://private.example/a і подзвони +380671234567")
        report.record("visible_result", "kind=handoff")

        let session = report.completedSession()
        #expect(session?.detailedDiagnosticsConsent == true)
        #expect(session?.finalSpeechTranscript?.contains("[REDACTED]") == true)
        #expect(session?.normalizedTranscript?.contains("[REDACTED]") == true)
        #expect(session?.finalSpeechTranscript?.contains("private.example") == false)
        #expect(session?.normalizedTranscript?.contains("380671234567") == false)
    }

    @Test @MainActor func completeProductionTraceExposesDecisionBoundariesAndOneTerminalState() {
        let report = LocalVoiceDiagnosticReport(localStore: makeStore())
        report.beginHomeRequest(generation: 14)
        report.record("normalization", "length=18")
        report.record("language_detection", "language=uk")
        report.record("morphology", "status=completed")
        report.record("structured_number_reconstruction", "count=1")
        report.record("entity_recovery", "domain=CONTACT candidate_count=2 confidence=ambiguous")
        report.record("canonical_semantic_frame", "action=contactLookup object=contact")
        report.record("candidate_capabilities", "count=1 capability=contactLookup")
        report.record("selected_capability", "capability=contactLookup")
        report.record("system_first_decision", "selected=true capability=contactLookup")
        report.record("generic_web_selected", "selected=false reason=canonical_non_web_intent")
        report.record("current_context_input", "input_type=none")
        report.record("permission_state", "permission=authorized")
        report.recordBoundaryPre("EXECUTOR", "capability=contactLookup")
        report.recordBoundaryPost("EXECUTOR", "capability=contactLookup status=success")
        report.recordBoundaryPre("RENDERER_ACTION", "capability=contactLookup")
        report.record("visible_result", "kind=deterministic")
        report.recordBoundaryPost("RENDERER_ACTION", "capability=contactLookup status=success")

        let session = report.completedSession()
        let markers = session?.events.map(\.marker) ?? []
        #expect(markers.first == "request_created")
        #expect(markers.contains("entity_recovery"))
        #expect(markers.contains("selected_capability"))
        #expect(markers.contains("generic_web_selected"))
        #expect(markers.contains("EXECUTOR_PRE"))
        #expect(markers.contains("EXECUTOR_POST"))
        #expect(markers.contains("RENDERER_ACTION_PRE"))
        #expect(markers.contains("RENDERER_ACTION_POST"))
        #expect(markers.last == "request_end")
        #expect(markers.filter { $0 == "terminal_request_state" }.count == 1)
        #expect(session?.terminalState == .success)
    }

    @Test @MainActor func interactiveContinuationRemainsCrashPersistentUntilRealCallback() {
        let store = makeStore()
        let report = LocalVoiceDiagnosticReport(localStore: store)
        report.beginHomeRequest(generation: 21)
        report.record("selected_capability", "capability=fileSearch")
        report.suspendForInteractiveContinuation("documents")
        report.record("visible_result", "kind=system_presentation")

        #expect(report.completedSession() == nil)
        #expect(store.activeSnapshot()?.terminal == false)
        #expect(store.activeSnapshot()?.lastStage == "visible_result")

        report.resumeInteractiveContinuation(generation: 22)
        report.recordBoundaryPre("FILES", "mechanism=UIDocumentPicker")
        report.recordBoundaryPost("FILES", "status=selected count=1")
        report.record("visible_result", "kind=document_selected")
        let completed = report.completedSession()
        #expect(completed?.requestGeneration == 22)
        #expect(completed?.requestID == completed?.sessionID)
        #expect(completed?.terminalState == .success)
        #expect(completed?.events.contains(where: { $0.marker == "interactive_continuation_suspended" }) == true)
        #expect(completed?.events.contains(where: { $0.marker == "interactive_continuation_resumed" }) == true)
    }

    @Test @MainActor func dismissedInteractiveContinuationHasOneCancelledTerminal() {
        let store = makeStore()
        let report = LocalVoiceDiagnosticReport(localStore: store)
        report.beginHomeRequest(generation: 31)
        report.suspendForInteractiveContinuation("scanner")
        #expect(report.finishInteractiveContinuation(.cancelled, details: "reason=user_dismissed"))
        #expect(!report.finishInteractiveContinuation(.cancelled))
        let session = report.completedSession()
        #expect(session?.terminalState == .cancelled)
        #expect(session?.events.filter { $0.marker == "terminal_request_state" }.count == 1)
        #expect(LocalVoiceDiagnosticReport(localStore: store).recoveredIncompleteSession() == nil)
    }

    @Test func mandatoryBoundaryMappingCoversCanonicalProductionFamilies() {
        let cases: [(StructuredCommand, String)] = [
            (.init(originalText: "", normalizedText: "", language: .uk, intent: .contactLookup), "CONTACT_RESOLUTION"),
            (.init(originalText: "", normalizedText: "", language: .uk, intent: .messageCompose), "MESSAGE_COMPOSE"),
            (.init(originalText: "", normalizedText: "", language: .uk, intent: .calendarCreate), "CALENDAR"),
            (.init(originalText: "", normalizedText: "", language: .uk, intent: .reminderCreate), "REMINDER"),
            (.init(originalText: "", normalizedText: "", language: .uk, intent: .photoSearch, entities: ["semantic_query": "receipt"]), "PHOTO_SEMANTIC_SEARCH"),
            (.init(originalText: "", normalizedText: "", language: .uk, intent: .fileSearch), "FILES"),
            (.init(originalText: "", normalizedText: "", language: .uk, intent: .translation), "TRANSLATION"),
            (.init(originalText: "", normalizedText: "", language: .uk, intent: .placeSearch), "MAPKIT_SEARCH"),
            (.init(originalText: "", normalizedText: "", language: .uk, intent: .navigation), "MAPKIT_ROUTE"),
            (.init(originalText: "", normalizedText: "", language: .uk, intent: .currencyConversion), "PROVIDER"),
            (.init(originalText: "", normalizedText: "", language: .uk, intent: .deviceAction, entities: ["system_action": "timer"]), "TIMER"),
            (.init(originalText: "", normalizedText: "", language: .uk, intent: .deviceAction, entities: ["system_action": "alarm"]), "ALARM"),
            (.init(originalText: "", normalizedText: "", language: .uk, intent: .deviceAction, entities: ["system_action": "clipboard_read"]), "CLIPBOARD")
        ]
        for (command, expected) in cases { #expect(DiagnosticBoundaryName.forCommand(command) == expected) }
    }

    @Test @MainActor func timeoutIsDurableAndClassifiedWithoutGuessingRootCause() {
        let report = LocalVoiceDiagnosticReport(localStore: makeStore())
        report.beginHomeRequest(generation: 15)
        report.record("selected_capability", "capability=photoSearch")
        report.recordTerminal(.timeout, details: "stage=executor")
        let session = report.completedSession()
        #expect(session?.terminalState == .timeout)
        #expect(session?.anomaly?.anomalyClass == .timeout)
        #expect(session?.anomaly?.certainty == .probableFailureBoundary)
    }

    @Test func anomalyAnalyzerUsesExplicitEvidenceAndAllowsDeliberateWeb() {
        let now = Date()
        let deliberate = [
            PhysicalDiagnosticEvent(sequence: 1, timestamp: now, marker: "generic_web_selected",
                                    attributes: ["selected": "true", "reason": "structured_general_or_web_intent"]),
            PhysicalDiagnosticEvent(sequence: 2, timestamp: now, marker: "terminal_request_state",
                                    attributes: ["state": "SUCCESS"])
        ]
        #expect(DiagnosticAnomalyAnalyzer.analyze(events: deliberate) == nil)

        let speechFailure = [
            PhysicalDiagnosticEvent(sequence: 1, timestamp: now, marker: "recognition_callback",
                                    attributes: ["error_domain": "kAFAssistantErrorDomain", "error_code": "1110"])
        ]
        #expect(DiagnosticAnomalyAnalyzer.analyze(events: speechFailure)?.anomalyClass == .asr)

        let entityFailure = [
            PhysicalDiagnosticEvent(sequence: 1, timestamp: now, marker: "entity_recovery",
                                    attributes: ["status": "failed", "reason": "confidence_below_threshold"])
        ]
        #expect(DiagnosticAnomalyAnalyzer.analyze(events: entityFailure)?.anomalyClass == .entityRecovery)

        let unexpectedWeb = [
            PhysicalDiagnosticEvent(sequence: 1, timestamp: now, marker: "generic_web_selected",
                                    attributes: ["selected": "true", "reason": "system_intent_fell_through"])
        ]
        #expect(DiagnosticAnomalyAnalyzer.analyze(events: unexpectedWeb)?.anomalyClass == .systemFirst)

        let missingProviderPost = [
            PhysicalDiagnosticEvent(sequence: 1, timestamp: now, marker: "PROVIDER_PRE", attributes: [:]),
            PhysicalDiagnosticEvent(sequence: 2, timestamp: now, marker: "terminal_request_state",
                                    attributes: ["state": "ERROR"])
        ]
        let provider = DiagnosticAnomalyAnalyzer.analyze(events: missingProviderPost)
        #expect(provider?.anomalyClass == .provider)
        #expect(provider?.reason == "missing_expected_post:PROVIDER_POST")
    }

    @Test func successfulAckPersistsReceiptAndPreventsDuplicateUpload() async {
        let suite = UserDefaults(suiteName: UUID().uuidString)!
        suite.set("test-key", forKey: "internal-app-attest-key-id")
        suite.set(true, forKey: "internal-app-attest-registered")
        let store = makeStore()
        let session = sampleSession()
        let transport = SuccessfulDiagnosticTransport(sessionID: session.sessionID)
        let delivery = PhysicalDiagnosticDelivery(attest: SupportedAttest(), transport: transport, defaults: suite, localStore: store, enabled: { true })
        let now = Date(timeIntervalSinceReferenceDate: 20_000)
        await delivery.enqueue(session, now: now)
        #expect(await delivery.pendingCount(now: now) == 0)
        #expect(store.receipts().map(\.sessionID) == [session.sessionID])
        #expect(store.deliveryStatus() == .uploaded)
        #expect(transport.diagnosticPostCount == 1)

        await delivery.enqueue(session, now: now.addingTimeInterval(1))
        #expect(await delivery.pendingCount(now: now.addingTimeInterval(1)) == 0)
        #expect(transport.diagnosticPostCount == 1)
    }

    @Test func serverRejectionKeepsLocalCopyAndExactStatus() async {
        let suite = UserDefaults(suiteName: UUID().uuidString)!
        suite.set("test-key", forKey: "internal-app-attest-key-id")
        suite.set(true, forKey: "internal-app-attest-registered")
        let store = makeStore()
        let delivery = PhysicalDiagnosticDelivery(attest: SupportedAttest(), transport: HTTPStatusTransport(statusCode: 422), defaults: suite, localStore: store, enabled: { true })
        let now = Date(timeIntervalSinceReferenceDate: 30_000)
        await delivery.enqueue(sampleSession(), now: now)
        #expect(await delivery.pendingCount(now: now) == 1)
        #expect(store.deliveryStatus() == .serverRejected)
        #expect(await delivery.state == .serverRejected)
    }

    @Test func metricKitPayloadIsBoundedRedactedAndDeduplicatedLocally() throws {
        let raw: [String: Any] = [
            "diagnosticMetaData": ["osVersion": "26.5", "deviceType": "iPhone"],
            "callStackTree": ["callStacks": [["callStackRootFrames": [["binaryName": "UniversalAssistant", "address": "private street"]]]]],
            "filePath": "/private/owner/file", "email": "owner@example.com", "tokenValue": "secret"
        ]
        let data = try JSONSerialization.data(withJSONObject: raw)
        let safe = try #require(PhysicalMetricKitDiagnostics.privacySafeJSON(data))
        #expect(safe.contains("[REDACTED]"))
        #expect(!safe.contains("owner@example.com"))
        #expect(!safe.contains("/private/owner/file"))
        #expect(safe.utf8.count <= 60_000)

        let store = makeStore()
        let fingerprint = String(repeating: "a", count: 64)
        #expect(store.addAppleDiagnostic(json: safe, fingerprint: fingerprint))
        #expect(!store.addAppleDiagnostic(json: safe, fingerprint: fingerprint))
    }


    @Test @MainActor func savedVoiceSessionPersistsCloudKitPendingBeforeActiveSnapshotClears() throws {
        let store = makeStore()
        let report = LocalVoiceDiagnosticReport(
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            persistenceKey: "saved-voice-cloudkit-pending",
            localStore: store
        )
        report.detailedDiagnosticsEnabled = true
        report.reset()
        report.record("start_listening_invoked")
        let requestID = try #require(store.activeSnapshot()?.requestID)
        try writeDiagnosticAudio(requestID: requestID, store: store)
        store.updateActive(
            sequence: 2,
            stage: "diagnostic_audio_finished",
            diagnosticAudioRelativePath: store.diagnosticAudioRelativePath(for: requestID),
            diagnosticAudioTruncated: false,
            diagnosticAudioDurationMilliseconds: 100
        )
        report.record("diagnostic_audio_finished", "status=saved")
        report.recordTerminal(.success)

        let session = try #require(report.completedSession())
        let pending = store.loadCloudKitAudioPending()
        #expect(session.requestID == requestID)
        #expect(pending.count == 1)
        #expect(pending.first?.metadata.requestID == requestID)
        #expect(store.activeSnapshot() == nil)
    }

    @Test func relaunchRecoveryRestoresMissingCloudKitPendingFromPersistedSession() async throws {
        let store = makeStore()
        let now = Date(timeIntervalSinceReferenceDate: 40_000)
        let session = try persistedVoiceAudioSession(store: store, now: now)
        store.addPending(queued(session, now: now))
        let delivery = PhysicalDiagnosticDelivery(
            attest: UnsupportedAttest(), transport: FailingTransport(),
            defaults: UserDefaults(suiteName: UUID().uuidString)!, localStore: store,
            enabled: { false }
        )

        #expect(store.loadCloudKitAudioPending().isEmpty)
        await delivery.restoreMissingCloudKitAudioPending(now: now)
        let pending = store.loadCloudKitAudioPending()
        #expect(pending.count == 1)
        #expect(pending.first?.metadata.requestID == session.requestID)
    }

    @Test func duplicateRecoveryDoesNotCreateSecondCloudKitPendingItem() async throws {
        let store = makeStore()
        let now = Date(timeIntervalSinceReferenceDate: 50_000)
        let session = try persistedVoiceAudioSession(store: store, now: now)
        store.addPending(queued(session, now: now))
        let delivery = PhysicalDiagnosticDelivery(
            attest: UnsupportedAttest(), transport: FailingTransport(),
            defaults: UserDefaults(suiteName: UUID().uuidString)!, localStore: store,
            enabled: { false }
        )

        await delivery.restoreMissingCloudKitAudioPending(now: now)
        await delivery.restoreMissingCloudKitAudioPending(now: now)
        #expect(store.loadCloudKitAudioPending().count == 1)
    }

    @Test @MainActor func recoveredAudioSessionPreservesVoiceFeature() throws {
        let store = makeStore()
        let report = LocalVoiceDiagnosticReport(
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            persistenceKey: "recovered-voice-feature",
            localStore: store
        )
        report.detailedDiagnosticsEnabled = true
        report.reset()
        report.record("start_listening_invoked")
        let requestID = try #require(store.activeSnapshot()?.requestID)
        try writeDiagnosticAudio(requestID: requestID, store: store)
        store.updateActive(
            sequence: 2,
            stage: "diagnostic_audio_finished",
            diagnosticAudioRelativePath: store.diagnosticAudioRelativePath(for: requestID),
            diagnosticAudioTruncated: false,
            diagnosticAudioDurationMilliseconds: 100
        )
        report.record("diagnostic_audio_finished", "status=saved")

        let recovered = try #require(report.recoveredIncompleteSession())
        #expect(recovered.requestID == requestID)
        #expect(recovered.feature == "voice")
    }

    @Test func emergencyExportIsAValidBoundedZipWithRequiredFiles() throws {
        let store = makeStore()
        store.append(.init(sequence: 1, timestamp: .now, marker: "request_created", attributes: ["source": "home"]), durable: true)
        let archiveURL = try DiagnosticExportBuilder.makeBuild32Package(store: store, now: Date(timeIntervalSince1970: 2_000))
        let data = try Data(contentsOf: archiveURL)
        #expect(data.prefix(4) == Data([0x50, 0x4b, 0x03, 0x04]))
        let visibleNames = String(decoding: data, as: UTF8.self)
        for required in ["manifest.json", "requests.jsonl", "analysis_summary.json", "last_unclean_request.json", "vps_delivery_status.json", "apple_diagnostics/status.json", "human_summary_uk.txt"] {
            #expect(visibleNames.contains(required))
        }
        #expect(archiveURL.pathExtension == "zip")
        #expect(archiveURL.lastPathComponent.hasPrefix("UniversalAssistant_Diagnostics_Build"))
    }

    private func sampleSession() -> PhysicalDiagnosticSession {
        .init(schema: 1, sessionID: UUID(), liveTestID: "MS-800-LIVE-VOICE-QA", feature: "voice", appVersion: "0.1.0", build: 10,
              environment: "internal-testflight", osVersion: "26.6.1", deviceClass: "iPhone", startedAt: .now, endedAt: .now,
              durationMilliseconds: 1, result: .failure, failureStage: "recognition_callback", errorDomain: "test", errorCode: 1,
              events: [.init(sequence: 1, timestamp: .now, marker: "recognition_callback", attributes: ["error_code": "1"])])
    }


    private func persistedVoiceAudioSession(
        store: PhysicalDiagnosticLocalStore,
        now: Date
    ) throws -> PhysicalDiagnosticSession {
        let requestID = UUID()
        try writeDiagnosticAudio(requestID: requestID, store: store)
        var session = PhysicalDiagnosticSession(
            schema: 2, sessionID: requestID, liveTestID: "BUILD37-CLOUDKIT-RECOVERY", feature: "voice",
            appVersion: "0.1.0", build: 37, environment: "internal-testflight",
            osVersion: "26.6.2", deviceClass: "iPhone12,8", startedAt: now, endedAt: now,
            durationMilliseconds: 100, result: .success, failureStage: nil, errorDomain: nil, errorCode: nil,
            events: [.init(sequence: 1, timestamp: now, marker: "diagnostic_audio_finished", attributes: ["status": "saved"])]
        )
        session.diagnosticSessionID = requestID
        session.requestID = requestID
        session.requestGeneration = 1
        session.terminalState = .success
        session.detailedDiagnosticsConsent = true
        session.diagnosticAudioRelativePath = store.diagnosticAudioRelativePath(for: requestID)
        session.diagnosticAudioTruncated = false
        session.diagnosticAudioDurationMilliseconds = 100
        return session
    }

    private func queued(_ session: PhysicalDiagnosticSession, now: Date) -> DiagnosticQueuedUpload {
        .init(
            session: session, attempts: 0, expiresAt: now.addingTimeInterval(86_400),
            nextAttemptAt: now, status: .pendingUpload, lastHTTPStatus: nil, errorCategory: nil
        )
    }

    private func writeDiagnosticAudio(requestID: UUID, store: PhysicalDiagnosticLocalStore) throws {
        try Data(repeating: 0x41, count: 128).write(to: store.diagnosticAudioURL(for: requestID), options: .atomic)
    }

    private func makeStore() -> PhysicalDiagnosticLocalStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ua-diagnostics-tests-\(UUID().uuidString)", isDirectory: true)
        return PhysicalDiagnosticLocalStore(rootDirectory: directory)
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
private struct HTTPStatusTransport: DiagnosticHTTPTransport {
    let statusCode: Int
    func post<Request, Response>(_ path: String, body: Request, response: Response.Type) async throws -> Response where Request: Encodable, Response: Decodable {
        throw PhysicalDiagnosticDeliveryError.httpFailure(statusCode: statusCode)
    }
}
private final class SuccessfulDiagnosticTransport: DiagnosticHTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let sessionID: UUID
    private var storedDiagnosticPostCount = 0
    var diagnosticPostCount: Int { lock.withLock { storedDiagnosticPostCount } }

    init(sessionID: UUID) { self.sessionID = sessionID }

    func post<Request, Response>(_ path: String, body: Request, response: Response.Type) async throws -> Response where Request: Encodable, Response: Decodable {
        let json: String
        switch path {
        case "v1/app-attest/challenge":
            json = #"{"challengeID":"00000000-0000-0000-0000-000000000001","challenge":"dGVzdA==","expiresAt":"2026-09-10T12:00:00Z"}"#
        case "v1/diagnostics":
            lock.withLock { storedDiagnosticPostCount += 1 }
            json = "{\"sessionID\":\"\(sessionID.uuidString)\",\"status\":\"delivered\",\"receivedAt\":\"2026-09-10T12:00:01Z\"}"
        default:
            throw PhysicalDiagnosticDeliveryError.httpFailure(statusCode: 404)
        }
        return try JSONDecoder.serverDiagnosticResponse.decode(Response.self, from: Data(json.utf8))
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
