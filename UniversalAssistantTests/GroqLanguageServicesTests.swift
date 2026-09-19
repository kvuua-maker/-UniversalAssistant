import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Groq language services boundary")
struct GroqLanguageServicesTests {
    @Test func groqTranscriptWinsAndAppleIsTheOnlyFallback() {
        #expect(VoiceAuthoritativeTranscriptSelector.select(
            groq: "  Відкрий Telegram  ", appleFallback: "Відкрий"
        ) == .init(text: "Відкрий Telegram", source: .groq))
        #expect(VoiceAuthoritativeTranscriptSelector.select(
            groq: nil, appleFallback: "  Відкрий Viber "
        ) == .init(text: "Відкрий Viber", source: .appleFallback))
        #expect(VoiceAuthoritativeTranscriptSelector.select(groq: "", appleFallback: "") == nil)
    }

    @Test func semanticModelCannotReplaceExplicitProviderOrBrand() async throws {
        let engine = FixedGroqSemanticEngine(frame: .init(
            requestID: UUID(), intent: "productSearch", action: "find", channel: nil,
            provider: "amazon", app: nil, contact: nil, entity: "сорочка",
            brand: "Prada", product: "сорочка", city: nil, date: nil, time: nil,
            quantity: nil, mediaAction: nil, query: "сорочка", ambiguous: false,
            model: "openai/gpt-oss-20b"
        ))
        let resolver = GroqGenericIntentResolver(engine: engine)
        let provider = try await resolver.resolve("Знайди Seiko на eBay")
        #expect(provider.brandOrProvider == "market.ebay")
        let brand = try await resolver.resolve("Купити сорочку Pierre Cardin")
        #expect(brand.brandOrProvider == "Pierre Cardin")
        #expect(brand.brandOrProvider != "Prada")
    }

    @Test func structuredSemanticCommandFeedsCanonicalRouterWithoutCrossChannelSubstitution() async throws {
        let engine = FixedGroqSemanticEngine(frame: .init(
            requestID: UUID(), intent: CommandIntent.contactCall.rawValue, action: "call", channel: "whatsapp",
            provider: nil, app: nil, contact: "маму", entity: nil, brand: nil, product: nil,
            city: nil, date: nil, time: nil, quantity: nil, mediaAction: nil, query: nil,
            ambiguous: false, model: "openai/gpt-oss-20b"
        ))
        let command = try await GroqSemanticCommandResolver(engine: engine)
            .resolveCommand("Набери маму через Viber", language: .uk)
        #expect(command.intent == .contactCall)
        #expect(command.entities["call_service"] == "viber")
        #expect(command.entities["call_service"] != "whatsapp")
        #expect(CanonicalRoutingPolicy().decide(command).lane == .appleSystem)
    }

    @Test func neverAISecretTextIsNotSentToGroq() async {
        let probe = SemanticInvocationProbe()
        let resolver = GroqGenericIntentResolver(engine: ProbingGroqSemanticEngine(probe: probe))
        await #expect(throws: GroqLanguageServiceError.privacyBlocked) {
            _ = try await resolver.resolve("api_key=super-secret")
        }
        #expect(await probe.count == 0)
    }
}

private struct FixedGroqSemanticEngine: CloudSemanticUnderstanding {
    let frame: CloudSemanticFrame
    func interpret(_ text: String, requestID: UUID) async throws -> CloudSemanticFrame {
        .init(requestID: requestID, intent: frame.intent, action: frame.action, channel: frame.channel,
              provider: frame.provider, app: frame.app, contact: frame.contact, entity: frame.entity,
              brand: frame.brand, product: frame.product, city: frame.city, date: frame.date,
              time: frame.time, quantity: frame.quantity, mediaAction: frame.mediaAction,
              query: frame.query, ambiguous: frame.ambiguous, model: frame.model)
    }
}

private actor SemanticInvocationProbe {
    private(set) var count = 0
    func invoked() { count += 1 }
}

private struct ProbingGroqSemanticEngine: CloudSemanticUnderstanding {
    let probe: SemanticInvocationProbe
    func interpret(_ text: String, requestID: UUID) async throws -> CloudSemanticFrame {
        await probe.invoked()
        throw URLError(.cannotConnectToHost)
    }
}
