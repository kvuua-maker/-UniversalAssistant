import Foundation
import Testing
@testable import UniversalAssistant

@MainActor
private final class CapabilityExecutorStub: CanonicalCapabilityExecuting {
    let outcome: Result<CapabilityExecutionOutcome, Error>
    private(set) var received: [CommandIntent] = []
    init(_ outcome: Result<CapabilityExecutionOutcome, Error>) { self.outcome = outcome }
    func execute(_ command: StructuredCommand) async throws -> CapabilityExecutionOutcome {
        received.append(command.intent)
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

    @Test func systemPresentationIsTypedAndDoesNotMasqueradeAsCompletedAction() async throws {
        let executor = CapabilityExecutorStub(.success(.presentation(.camera)))
        let model = AssistantViewModel(capabilityExecutor: executor)
        model.input = "Зроби фото"
        model.submit()
        try await waitUntil { model.capabilityPresentation == .camera }
        #expect(executor.received == [.cameraCapture])
    }

    @Test func simpleProductRequestUsesTruthfulCurrentSourceFallbackWithoutMultiStepLeakage() async throws {
        let executor = CapabilityExecutorStub(.failure(CanonicalCapabilityExecutionError.externalProviderRequired("productSearch")))
        let model = AssistantViewModel(capabilityExecutor: executor)
        model.input = "Знайди iPhone 17 Pro"
        model.submit()
        try await waitUntil { if case .webHandoff = model.resultState { true } else { false } }
        #expect(executor.received == [.productSearch])
        guard case let .webHandoff(result) = model.resultState else { return }
        #expect(result.query == "Знайди iPhone 17 Pro")
        #expect(!result.query.contains("typedCommand"))
        #expect(!result.query.contains("deterministicCompose"))
    }

    @Test func externalProviderRequirementUsesTruthfulWebFallback() async throws {
        let executor = CapabilityExecutorStub(.failure(CanonicalCapabilityExecutionError.externalProviderRequired("productSearch")))
        let model = AssistantViewModel(capabilityExecutor: executor)
        model.input = "Знайди черевики"
        model.submit()
        try await waitUntil { if case .webHandoff = model.resultState { true } else { false } }
        #expect(executor.received == [.productSearch])
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
