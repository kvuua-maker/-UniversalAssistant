import Foundation
import Testing
import UIKit
@testable import UniversalAssistant

@MainActor
private final class CapabilityExecutorStub: CanonicalCapabilityExecuting {
    let outcome: Result<CapabilityExecutionOutcome, Error>
    private(set) var received: [CommandIntent] = []
    private(set) var commands: [StructuredCommand] = []
    init(_ outcome: Result<CapabilityExecutionOutcome, Error>) { self.outcome = outcome }
    func execute(_ command: StructuredCommand) async throws -> CapabilityExecutionOutcome {
        received.append(command.intent)
        commands.append(command)
        return try outcome.get()
    }
}

@MainActor
struct CanonicalCapabilityExecutionTests {
    @Test func parserGeneralizesCanonicalDeviceClassesAcrossUkrainianAndRussian() {
        let parser = LocalCommandEngine()
        #expect(parser.parse("Зроби фото").intent == .cameraCapture)
        #expect(parser.parse("Найди фотографии с моря").intent == .photoSearch)
        #expect(parser.parse("Знайди документ Договір").intent == .fileSearch)
        #expect(parser.parse("Включи музыку Океан Эльзы").intent == .mediaSearch)
        #expect(parser.parse("Знайди подкаст про історію").intent == .podcastSearch)
        #expect(parser.parse("Отследи посылку AB123456789CD").intent == .parcelTrack)
    }

    @Test func unseenCaptureVariantsReachPublicVisibleCameraWithoutClaimingAutomaticCapture() async throws {
        let parser = LocalCommandEngine()
        for phrase in ["Зніми портретну фотографію", "Сними новый снимок", "Capture an image"] {
            let command = parser.parse(phrase)
            #expect(command.intent == .cameraCapture)
            #expect(try await ProductionCanonicalCapabilityExecutor(personalSearchSources: []).execute(command) == .presentation(.camera))
        }
    }

    @Test func musicRecognitionRemainsSeparateFromPlaybackAndNeverFallsToWeb() async throws {
        let parser = LocalCommandEngine()
        for phrase in ["Визнач, яка композиція зараз грає", "Определи этот музыкальный трек", "Identify the playing song"] {
            let command = parser.parse(phrase)
            #expect(command.intent == .musicRecognition)
            guard case let .result(result) = try await ProductionCanonicalCapabilityExecutor(personalSearchSources: []).execute(command) else {
                Issue.record("Expected truthful local ShazamKit dependency result")
                continue
            }
            #expect(result.primaryAnswer.localizedCaseInsensitiveContains("ShazamKit"))
            #expect(result.actions.isEmpty)
        }
        #expect(parser.parse("Увімкни альбом у Apple Music").intent == .mediaSearch)
    }

    @Test func parsedCapabilityUsesProductionExecutionBoundary() async throws {
        let fact = ResultFact(id: "one", label: "Result", value: "Verified", state: .verified,
                              source: "test-source", observedAt: .now, priority: 1)
        let value = try DeterministicResultComposer().compose(primaryAnswer: "Done", facts: [fact])
        let executor = CapabilityExecutorStub(.success(.result(value)))
        let model = AssistantViewModel(capabilityExecutor: executor)
        model.input = "Знайди контакт Олена"
        model.submit()
        try await waitUntil { if case .deterministic = model.resultState { true } else { false } }
        #expect(executor.received == [.contactLookup])
    }

    @Test func settingsTargetUsesOnlyDocumentedTargetSpecificHandoff() async throws {
        let parser = LocalCommandEngine()
        let executor = ProductionCanonicalCapabilityExecutor(personalSearchSources: [])

        let application = parser.parse("Відкрий дозволи цього застосунку")
        #expect(application.intent == .settings)
        #expect(application.entities["settings_target"] == "application")
        guard case let .handoff(handoff) = try await executor.execute(application) else {
            Issue.record("Expected the documented application-settings handoff")
            return
        }
        #expect(handoff.destination.absoluteString == UIApplication.openSettingsURLString)

        for phrase in ["Покажи системні параметри телефону", "Перейди до параметрів мережі", "Open the device privacy settings"] {
            let command = parser.parse(phrase)
            #expect(command.intent == .settings)
            #expect(command.entities["settings_target"] == "system")
            await #expect(throws: CanonicalCapabilityExecutionError.unavailable("system_settings_destination_not_publicly_available")) {
                try await executor.execute(command)
            }
            #expect(command.intent != .webSearch)
        }
    }

    @Test func unseenTemporalNumericAndContextRolesReachProductionBoundary() async throws {
        let fact = ResultFact(id: "roles", label: "Result", value: "Verified", state: .verified,
                              source: "test-source", observedAt: .now, priority: 1)
        let value = try DeterministicResultComposer().compose(primaryAnswer: "Done", facts: [fact])
        let executor = CapabilityExecutorStub(.success(.result(value)))
        let model = AssistantViewModel(capabilityExecutor: executor)

        model.input = "Запусти таймер на 1,5 хвилини для заварювання"
        model.submit()
        try await waitUntil { executor.commands.count == 1 }
        #expect(executor.commands[0].intent == .deviceAction)
        #expect(executor.commands[0].entities["temporal_expression"] != nil)

        model.input = "Покажи банкомати по дорозі"
        model.submit()
        try await waitUntil { executor.commands.count == 2 }
        #expect(executor.commands[1].entities["context_reference"] == "activeRoute")
        #expect(executor.commands[1].intent != .webSearch)
    }

    @Test func unseenRoleCollisionsReachOneCanonicalHomeBoundary() async throws {
        let fact = ResultFact(id: "frame", label: "Result", value: "Verified", state: .verified,
                              source: "test-source", observedAt: .now, priority: 1)
        let value = try DeterministicResultComposer().compose(primaryAnswer: "Done", facts: [fact])
        let cases: [(String, CommandIntent, [String: String])] = [
            ("Пошукай гарантійні талони серед фотографій", .photoSearch, [:]),
            ("Дозволь обрати звіт із iCloud Drive", .fileSearch, [:]),
            ("Покажи контакт Лесі", .contactLookup, [:]),
            ("Набери Лесю", .contactCall, [:]),
            ("Зателефонуй Лесі через WhatsApp", .contactCall, ["call_service": "whatsapp"]),
            ("Встанови будильник на 06:40", .deviceAction, ["system_action": "alarm"]),
            ("Прочитай текст камерою", .cameraCapture, ["capture_mode": "text_scan"]),
            ("Проскануй штрихкод упаковки", .cameraCapture, ["capture_mode": "code_scan"]),
            ("Оцифруй паперовий документ", .cameraCapture, ["input_source": "document_camera"]),
            ("Скільки доступного простору лишилося на пристрої", .deviceAction, ["system_action": "storage"]),
            ("Покажи стан акумулятора пристрою", .deviceAction, ["system_action": "battery"])
        ]

        for item in cases {
            let executor = CapabilityExecutorStub(.success(.result(value)))
            let model = AssistantViewModel(capabilityExecutor: executor)
            model.input = item.0
            model.submit()
            try await waitUntil { executor.commands.count == 1 }
            let command = try #require(executor.commands.last)
            #expect(command.intent == item.1)
            for (key, expected) in item.2 { #expect(command.entities[key] == expected) }
            #expect(command.intent != .webSearch)
        }
    }

    @Test func systemPresentationIsTypedAndDoesNotMasqueradeAsCompletedAction() async throws {
        let executor = CapabilityExecutorStub(.success(.presentation(.camera)))
        let model = AssistantViewModel(capabilityExecutor: executor)
        model.input = "Зроби фото"
        model.submit()
        try await waitUntil { model.capabilityPresentation == .camera }
        #expect(executor.received == [.cameraCapture])
    }

    @Test func simpleProductRequestStopsAtTruthfulProviderBoundaryWithoutMultiStepLeakage() async throws {
        let executor = CapabilityExecutorStub(.failure(CanonicalCapabilityExecutionError.externalProviderRequired("productSearch")))
        let model = AssistantViewModel(capabilityExecutor: executor)
        model.input = "Знайди iPhone 17 Pro"
        model.submit()
        try await waitUntil { if case .failure = model.resultState { true } else { false } }
        #expect(executor.received == [.productSearch])
        guard case let .failure(result) = model.resultState else { return }
        #expect(result.message.contains("провайдер"))
    }

    @Test func externalProductProviderRequirementNeverUsesGenericWebAsErrorHandler() async throws {
        let executor = CapabilityExecutorStub(.failure(CanonicalCapabilityExecutionError.externalProviderRequired("productSearch")))
        let model = AssistantViewModel(capabilityExecutor: executor)
        model.input = "Знайди черевики"
        model.submit()
        try await waitUntil { if case .failure = model.resultState { true } else { false } }
        #expect(executor.received == [.productSearch])
        #expect({ if case .webHandoff = model.resultState { return false }; return true }())
    }

    @Test func verifiedSystemHandoffExecutesImmediatelyWithoutNarrationCard() async throws {
        let destination = try #require(URL(string: "https://www.youtube.com"))
        let executor = CapabilityExecutorStub(.success(.handoff(.init(query: "Відкрий YouTube", destination: destination, kind: .system))))
        var opened: URL?
        let model = AssistantViewModel(capabilityExecutor: executor, systemHandoffOpen: { opened = $0 })
        model.input = "Відкрий програму YouTube"
        model.submit()
        try await waitUntil { opened == destination }
        #expect(model.resultState == AssistantResultState.idle)
        #expect(executor.received == [.open])
    }

    @Test func directHTTPSInputBypassesGenericSearchAndUnsafeSchemesDoNot() async throws {
        let command = LocalCommandEngine().parse("https://support.apple.com/uk-ua/")
        #expect(command.intent == .open)
        #expect(command.entities["direct_url"] == "https://support.apple.com/uk-ua/")
        let executor = ProductionCanonicalCapabilityExecutor(personalSearchSources: [])
        guard case let .handoff(handoff) = try await executor.execute(command) else { Issue.record("Expected direct HTTPS handoff"); return }
        #expect(handoff.kind == .system)
        #expect(handoff.destination.host == "support.apple.com")

        let unsafe = LocalCommandEngine().parse("javascript:alert(1)")
        #expect(unsafe.entities["direct_url"] == nil)
        #expect(unsafe.intent == .unknown)
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for ViewModel state")
    }
}
