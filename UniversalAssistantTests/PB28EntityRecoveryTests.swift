import Foundation
import Testing
@testable import UniversalAssistant

@Suite("PB28 context-scoped entity recovery")
struct PB28EntityRecoveryTests {
    @Test func serviceNoiseResolvesOnlyInsideServiceRole() {
        // Production voice and typed input are authoritative only after the
        // LanguageUnderstandingBlock. The legacy parser is a bounded candidate
        // generator inside that block and is not a separate semantic contract.
        let command = LanguageUnderstandingBlock().parse("Зателефонуй Маркові через whatsap")
        #expect(command.intent == .contactCall)
        #expect(command.entities["contact"] == "Маркові")
        #expect(command.entities["call_service"] == "whatsapp")
        #expect(!command.needsClarification)
    }

    @Test func weakEntityDoesNotBecomeMessengerOrWebIntent() {
        let command = LanguageUnderstandingBlock().parse("Набери Ірину через невідомий канал")
        #expect(command.intent == .contactCall)
        #expect(command.entities["call_service"] == nil)
        #expect(command.intent != .webSearch)
    }

    @Test func verifiedCatalogDomainCanResolveWithoutInventingBrand() {
        let candidates = [
            ScopedEntityCandidate(value: "maison-aurelia", displayName: "Maison Aurelia", aliases: ["Maison Aurelia"]),
            ScopedEntityCandidate(value: "atelier-aurora", displayName: "Atelier Aurora", aliases: ["Atelier Aurora"])
        ]
        let resolver = ContextScopedEntityResolver(candidates: candidates)
        #expect(resolver.resolve("Maison Aurela") == .resolved("maison-aurelia"))
        #expect(resolver.resolve("pretty shoes") == .unresolved)
    }

    @Test func closeVerifiedCandidatesProduceConciseAmbiguity() {
        let candidates = [
            ScopedEntityCandidate(value: 1, displayName: "Nova Market", aliases: ["Nova"]),
            ScopedEntityCandidate(value: 2, displayName: "Novo Market", aliases: ["Novo"])
        ]
        guard case let .ambiguous(options) = ContextScopedEntityResolver(candidates: candidates).resolve("Nov") else {
            Issue.record("Expected ambiguity inside the verified domain"); return
        }
        #expect(options == ["Nova Market", "Novo Market"])
    }
}
