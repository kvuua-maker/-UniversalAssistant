import Foundation

enum UnresolvedSemanticReason: String, Codable, Sendable { case ambiguousRelativeTerm, unsupportedLanguageStructure }
struct UnresolvedInterpretation: Equatable, Codable, Sendable {
    let commandID: UUID; let text: String; let reason: UnresolvedSemanticReason; let allowedConstraintKeys: Set<String>
}
struct AIConstraintInterpretation: Equatable, Codable, Sendable {
    let key: String; let value: String; let confidence: Double
}
struct AIInterpretationResponse: Equatable, Codable, Sendable { let constraints: [AIConstraintInterpretation] }

protocol AIInterpretationProvider: Sendable {
    func interpret(_ unresolved: UnresolvedInterpretation) async throws -> AIInterpretationResponse
}

enum BoundedInterpretationOutcome: Equatable, Sendable {
    case resolved([ResolvedPlanConstraint], invocationCount: Int)
    case deterministicFallback(reason: String, invocationCount: Int)
}
enum AIInterpretationValidationError: Error { case timeout }

struct BoundedAIInterpreter: Sendable {
    let provider: any AIInterpretationProvider
    let timeout: Duration
    let privacyGate: PrivacyOutboundGate

    init(provider: any AIInterpretationProvider, timeout: Duration = .seconds(2), privacyGate: PrivacyOutboundGate = .init()) {
        self.provider = provider; self.timeout = timeout; self.privacyGate = privacyGate
    }

    func resolve(_ unresolved: UnresolvedInterpretation?) async -> BoundedInterpretationOutcome {
        guard let unresolved else { return .resolved([], invocationCount: 0) }
        guard !unresolved.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !unresolved.allowedConstraintKeys.isEmpty else {
            return .deterministicFallback(reason: "invalid_unresolved_contract", invocationCount: 0)
        }
        do {
            let safeText = privacyGate.sanitizeUntrustedContent(unresolved.text)
            let privacy = try privacyGate.evaluate(.init(destination: .ai(providerID: "bounded-interpretation"), purpose: "semantic_interpretation", fields: [.init(id: "text", name: "request_text", value: safeText, classification: .personal, purpose: "semantic_interpretation", requiredForSemantics: true)], consent: .granted, permittedPurposes: ["semantic_interpretation"], maxPersonalFields: 1, contentTrust: .trustedLocal))
            guard let permittedText = privacy.allowedFields.first?.value, !permittedText.isEmpty else { return .deterministicFallback(reason: "privacy_gate_blocked", invocationCount: 0) }
            let safe = UnresolvedInterpretation(commandID: unresolved.commandID, text: permittedText, reason: unresolved.reason, allowedConstraintKeys: unresolved.allowedConstraintKeys)
            let response = try await oneRequest(safe)
            guard !response.constraints.isEmpty,
                  response.constraints.allSatisfy({ unresolved.allowedConstraintKeys.contains($0.key) && !$0.value.isEmpty && (0...1).contains($0.confidence) }) else {
                return .deterministicFallback(reason: "schema_validation_failed", invocationCount: 1)
            }
            return .resolved(response.constraints.map {
                .init(key: $0.key, value: $0.value, strength: .soft, source: "bounded_ai_interpretation")
            }, invocationCount: 1)
        } catch {
            return .deterministicFallback(reason: "ai_timeout_or_unavailable", invocationCount: 1)
        }
    }

    private func oneRequest(_ unresolved: UnresolvedInterpretation) async throws -> AIInterpretationResponse {
        try await withThrowingTaskGroup(of: AIInterpretationResponse.self) { group in
            group.addTask { try await provider.interpret(unresolved) }
            group.addTask { try await Task.sleep(for: timeout); throw AIInterpretationValidationError.timeout }
            guard let first = try await group.next() else { throw AIInterpretationValidationError.timeout }
            group.cancelAll(); return first
        }
    }
}
