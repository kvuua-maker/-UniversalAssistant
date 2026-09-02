import Testing
@testable import UniversalAssistant

private actor AIInterpretationFixture: AIInterpretationProvider {
    let response: AIInterpretationResponse; let delay: Duration
    private(set) var calls = 0
    init(response: AIInterpretationResponse, delay: Duration = .zero) { self.response = response; self.delay = delay }
    func interpret(_ unresolved: UnresolvedInterpretation) async throws -> AIInterpretationResponse {
        calls += 1; if delay > .zero { try await Task.sleep(for: delay) }; return response
    }
}

@Suite("Bounded AI interpretation fallback")
struct BoundedAIInterpretationTests {
    @Test func deterministicResolutionMakesZeroAICalls() async {
        let provider = AIInterpretationFixture(response: .init(constraints: []))
        let outcome = await BoundedAIInterpreter(provider: provider).resolve(nil)
        #expect(outcome == .resolved([], invocationCount: 0))
        #expect(await provider.calls == 0)
    }

    @Test func unresolvedCaseMakesExactlyOneValidatedCall() async {
        let provider = AIInterpretationFixture(response: .init(constraints: [.init(key: "warmthPreference", value: "mild", confidence: 0.8)]))
        let unresolved = UnresolvedInterpretation(commandID: .init(), text: "щоб було тепло", reason: .ambiguousRelativeTerm, allowedConstraintKeys: ["warmthPreference"])
        let outcome = await BoundedAIInterpreter(provider: provider).resolve(unresolved)
        guard case .resolved(let constraints, invocationCount: 1) = outcome else { Issue.record("Expected one resolved call"); return }
        #expect(constraints.first?.source == "bounded_ai_interpretation")
        #expect(await provider.calls == 1)
    }

    @Test func invalidSchemaFallsBackWithoutSecondCall() async {
        let provider = AIInterpretationFixture(response: .init(constraints: [.init(key: "livePrice", value: "99", confidence: 1)]))
        let unresolved = UnresolvedInterpretation(commandID: .init(), text: "тепло", reason: .ambiguousRelativeTerm, allowedConstraintKeys: ["warmthPreference"])
        #expect(await BoundedAIInterpreter(provider: provider).resolve(unresolved) == .deterministicFallback(reason: "schema_validation_failed", invocationCount: 1))
        #expect(await provider.calls == 1)
    }

    @Test func timeoutReturnsDeterministicFallbackWithoutHanging() async {
        let provider = AIInterpretationFixture(response: .init(constraints: []), delay: .seconds(1))
        let unresolved = UnresolvedInterpretation(commandID: .init(), text: "ambiguous", reason: .unsupportedLanguageStructure, allowedConstraintKeys: ["category"])
        #expect(await BoundedAIInterpreter(provider: provider, timeout: .milliseconds(20)).resolve(unresolved) == .deterministicFallback(reason: "ai_timeout_or_unavailable", invocationCount: 1))
        #expect(await provider.calls == 1)
    }
}
