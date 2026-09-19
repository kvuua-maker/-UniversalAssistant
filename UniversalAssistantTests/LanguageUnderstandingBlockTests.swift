import Foundation
import Testing
import UIKit
@testable import UniversalAssistant

@Suite("Build 31 authoritative language understanding")
struct LanguageUnderstandingBlockTests {
    @Test func unicodeTokensAndStructuredNumbersRetainEvidence() {
        let original = "  Порахуй—12,5% від 5 600  "
        let document = LanguageUnderstandingBlock.document(original)
        #expect(document.originalText == original)
        #expect(document.normalizedText.contains("5600"))
        #expect(document.normalizedText.contains("12,5%"))
        #expect(document.tokens.contains(where: { $0.surface == "Порахуй" }))
    }

    @Test func mixedUkrainianAndLatinEntityDoesNotForceRussian() {
        let document = LanguageUnderstandingBlock.document("Покажи Spotify у моїй медіатеці")
        #expect(document.language == .uk)
        #expect(document.tokens.contains(where: { $0.normalized == "spotify" }))
    }

    @Test func verifiedDomainUsesTransliterationAndConfidenceMargin() {
        let candidates = [
            ScopedEntityCandidate(value: "foton", displayName: "Foton", aliases: ["Foton"]),
            ScopedEntityCandidate(value: "lumen", displayName: "Lumen", aliases: ["Lumen"])
        ]
        let evidence = ContextScopedEntityResolver(candidates: candidates).resolveWithEvidence("Фотон")
        #expect(evidence.resolution == .resolved("foton"))
        #expect(evidence.mechanism == .transliteration)
        #expect(evidence.bestScore >= 0.72)
        #expect(evidence.confidenceMargin >= 0.12)
    }

    @Test func closeAndWeakCandidatesClarifyOrFailClosed() {
        let close = [
            ScopedEntityCandidate(value: 1, displayName: "Aurora One", aliases: ["Aurora"]),
            ScopedEntityCandidate(value: 2, displayName: "Aurora Two", aliases: ["Aurora"])
        ]
        guard case let .ambiguous(options) = ContextScopedEntityResolver(candidates: close).resolve("Aurora") else {
            Issue.record("Expected a domain-bounded ambiguity")
            return
        }
        #expect(options == ["Aurora One", "Aurora Two"])

        let weak = ContextScopedEntityResolver(candidates: close).resolve("unrelated entity")
        #expect(weak == .unresolved)
    }

    @Test func morphologyPreservesTypedContactRole() {
        let command = LanguageUnderstandingBlock().parse("Набери Христині")
        #expect(command.intent == .contactCall)
        #expect(command.entities["contact"] == "Христині")
        #expect(!command.needsClarification)
        #expect(command.entities["language_understanding_version"] == "1")
    }

    @Test func semanticPhotoIsNotReplacedByLatestPhoto() {
        let command = LanguageUnderstandingBlock().parse("Пошукай старий міст серед моїх світлин")
        #expect(command.intent == .photoSearch)
        #expect(command.entities["query"] != "recent")
        #expect(command.intent != .fileSearch)
    }

    @Test func protectedUnknownTargetNeverBecomesGenericWeb() {
        let command = LanguageUnderstandingBlock().parse("Відкрий невідому панель керування пристроєм")
        #expect(command.intent == .open)
        #expect(command.needsClarification)
        #expect(command.intent != .webSearch)
    }

    @Test func speechAlternativeCanCompleteOnlyTheSameTypedIntentFamily() {
        let evidence = VoiceRecognitionEvidence(
            primaryTranscript: "Запусти невідоме",
            alternativeTranscripts: ["Запусти Спотіфа", "Постав будильник на сьому"],
            segmentAlternativeCount: 3,
            averageSegmentConfidence: 0.42
        )
        let command = LanguageUnderstandingBlock().parse("Запусти невідоме", speechEvidence: evidence)
        #expect(command.intent == .open)
        #expect(command.entities["app"] == "spotify")
        #expect(command.entities["speech_selected_alternative"] == "true")
        #expect(command.entities["speech_alternative_count"] == "2")
        #expect(command.intent != .deviceAction)
    }

    @Test func noisyExplicitServiceRecoversOnlyInsideCommunicationRole() {
        let services = [
            ScopedEntityCandidate(value: "channel-a", displayName: "Channel A", aliases: ["Velora"]),
            ScopedEntityCandidate(value: "channel-b", displayName: "Channel B", aliases: ["Nexora"])
        ]
        let parser = LanguageUnderstandingBlock(serviceCandidates: services)
        let call = parser.parse("Набери Олену через Велора")
        #expect(call.intent == .contactCall)
        #expect(call.entities["call_service"] == "channel-a")
        #expect(!call.needsClarification)

        let unrelated = parser.parse("Покажи календар Велора")
        #expect(unrelated.entities["call_service"] == nil)
        #expect(unrelated.entities["message_service"] == nil)
    }

    @Test func verifiedLocalizedServiceAliasPreservesExplicitChannel() {
        let command = LanguageUnderstandingBlock().parse("Набери Олену через Вайбера")
        #expect(command.intent == .contactCall)
        #expect(command.entities["call_service"] == "viber")
        #expect(command.entities["call_service"] != "whatsapp")
        #expect(!command.needsClarification)
    }

    @Test func configuredCatalogEntityRecoveryPreservesTypedKindAndFailsClosedWhenWeak() {
        let brands = [
            ScopedEntityCandidate(
                value: CanonicalCatalogEntity(id: "brand.alpina", displayName: "Alpina", kind: .brand),
                displayName: "Alpina",
                aliases: ["Alpina"]
            ),
            ScopedEntityCandidate(
                value: CanonicalCatalogEntity(id: "brand.velora", displayName: "Velora", kind: .brand),
                displayName: "Velora",
                aliases: ["Velora"]
            )
        ]
        let parser = LanguageUnderstandingBlock(catalogCandidates: brands)
        let recovered = parser.parse("Знайди куртку Альпіна")
        #expect([CommandIntent.productSearch, .fashionDiscovery].contains(recovered.intent))
        #expect(recovered.entities["brand"] == "Alpina")
        #expect(recovered.constraints.brand == "Alpina")
        #expect(recovered.constraints.hardConstraintKeys.contains("brand"))

        let weak = parser.parse("Знайди звичайну зимову куртку")
        #expect(weak.entities["brand"] == nil)
        #expect(weak.constraints.brand == nil)
    }
}

@MainActor
private final class Build31LanguageOpenCapture {
    private(set) var urls: [URL] = []
    func open(_ url: URL) { urls.append(url) }
}

@Suite("Build 31 Release-root language authority", .serialized)
@MainActor
struct Build31ReleaseRootLanguageTests {
    private func wait(_ predicate: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<150 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Release-root request did not terminate")
    }

    @Test func noisyVerifiedApplicationUsesShippedLanguageBlockAndHandoff() async throws {
        let capture = Build31LanguageOpenCapture()
        let model = ProductionAssistantComposition.makeModel(
            personalSearchSources: [],
            compactResultDuration: .seconds(60),
            systemHandoffOpen: capture.open
        )
        model.input = "Запусти Спотіфа"
        model.submit()
        try await wait { !capture.urls.isEmpty || model.statusText == AppText.value("clarification_needed") }
        #expect(capture.urls.first?.scheme == "spotify")
        #expect(model.statusText != AppText.value("processing"))
        #expect({ if case .webHandoff = model.resultState { return false }; return true }())
    }

    @Test func unknownSystemTargetTerminatesAsClarificationWithoutWeb() async throws {
        let model = ProductionAssistantComposition.makeModel(
            personalSearchSources: [],
            compactResultDuration: .seconds(60)
        )
        model.input = "Відкрий невідому панель керування пристроєм"
        model.submit()
        try await wait { model.statusText != AppText.value("processing") }
        #expect(model.statusText == AppText.value("clarification_needed"))
        #expect({ if case .webHandoff = model.resultState { return false }; return true }())
    }
}
