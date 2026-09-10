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

    @Test func productiveInflectionsRemainEvidenceInsteadOfPhraseAliases() {
        let document = LanguageUnderstandingBlock.document(
            "Відскануйте договір та повідомте Христині через захищений канал"
        )
        let bySurface = Dictionary(uniqueKeysWithValues: document.tokens.map { ($0.surface, $0.morphologyForms) })
        #expect(bySurface["Відскануйте"]?.contains("відскану") == true)
        #expect(bySurface["Христині"]?.contains("христин") == true)

        let scan = LanguageUnderstandingBlock().parse("Відскануйте текст камерою")
        #expect(scan.intent == .cameraCapture)
        #expect(scan.entities["capture_mode"] == "text_scan")
        #expect(scan.intent != .webSearch)
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

        let marginBound = [
            ScopedEntityCandidate(value: 3, displayName: "bcdfghjkln", aliases: []),
            ScopedEntityCandidate(value: 4, displayName: "bcdfghjkzz", aliases: [])
        ]
        guard case let .ambiguous(marginOptions) = ContextScopedEntityResolver(candidates: marginBound)
            .resolve("bcdfghjklm") else {
            Issue.record("Expected both candidates inside the required confidence margin")
            return
        }
        #expect(marginOptions == ["bcdfghjkln", "bcdfghjkzz"])

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
        #expect(command.entities["photo_query_kind"] == "semantic")
        #expect(command.entities["query"] == "старий міст")
        #expect(command.intent != .fileSearch)
    }

    @Test func contentBearingShowStaysSemanticWhileGenericPhotoRemainsRecent() {
        let semantic = LanguageUnderstandingBlock().parse("Покажи серед світлин старовинну вежу")
        #expect(semantic.intent == .photoSearch)
        #expect(semantic.entities["photo_query_kind"] == "semantic")
        #expect(semantic.entities["query"] == "старовинну вежу")

        let recent = LanguageUnderstandingBlock().parse("Покажи мою фотографію")
        #expect(recent.intent == .photoSearch)
        #expect(recent.entities["photo_query_kind"] == "recent")
        #expect(recent.entities["query"] == "recent")
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

    @Test func noisyServiceResolvesOnlyAfterCommunicationRoleAndExplicitChannelScope() {
        let block = LanguageUnderstandingBlock(serviceCandidates: [
            .init(value: "matrix", displayName: "Matrix", aliases: ["Matrix"]),
            .init(value: "secure-chat", displayName: "Secure Chat", aliases: ["Secure Chat"])
        ])
        let command = block.parse("Надішли повідомлення Маркові через Matr")
        #expect(command.intent == .messageCompose)
        #expect(command.entities["recipient"] == "Маркові")
        #expect(command.entities["message_service"] == "matrix")
        #expect(command.entities["service_match_confidence"].flatMap(Double.init) ?? 0 >= 0.72)
        #expect(!command.needsClarification)
    }

    @Test func messageRolesSeparateRecipientBodyAndServiceWithoutPhraseAliases() {
        let block = LanguageUnderstandingBlock(serviceCandidates: [
            .init(value: "matrix", displayName: "Matrix", aliases: ["Matrix"])
        ])
        let variants: [(String, String, String)] = [
            ("Напиши Дарині: перенесемо зустріч на вечір", "Дарині", "перенесемо зустріч на вечір"),
            ("Надішли повідомлення для Ірини про готовність звіту", "Ірини", "про готовність звіту"),
            ("Message Rowan that the parcel arrived", "Rowan", "the parcel arrived")
        ]
        for (text, recipient, body) in variants {
            let command = block.parse(text)
            #expect(command.intent == .messageCompose)
            #expect(command.entities["recipient"] == recipient)
            #expect(command.entities["message_body"] == body)
            #expect(command.intent != .webSearch)
        }

        let service = block.parse("Надішли Оксані повідомлення про реліз через Matr")
        #expect(service.entities["recipient"] == "Оксані")
        #expect(service.entities["message_body"] == "про реліз")
        #expect(service.entities["message_service"] == "matrix")
    }

    @Test func personWithoutChannelMarkerNeverBecomesMessenger() {
        let block = LanguageUnderstandingBlock(serviceCandidates: [
            .init(value: "oleksii-service", displayName: "Oleksii", aliases: ["Олексій"])
        ])
        let command = block.parse("Набери Олексію")
        #expect(command.intent == .contactCall)
        #expect(command.entities["contact"] == "Олексію")
        #expect(command.entities["call_service"] == nil)
        #expect(command.intent != .webSearch)
    }

    @Test func closeServiceCandidatesRequireClarification() {
        let block = LanguageUnderstandingBlock(serviceCandidates: [
            .init(value: "relay-one", displayName: "Relay One", aliases: ["Relay"]),
            .init(value: "relay-two", displayName: "Relay Two", aliases: ["Relay"])
        ])
        let command = block.parse("Відправ повідомлення Дарині через Relay")
        #expect(command.intent == .messageCompose)
        #expect(command.needsClarification)
        #expect(command.entities["clarification_options"] == "Relay One|Relay Two")
        #expect(command.intent != .webSearch)
    }

    @Test func verifiedCatalogCandidateBecomesTypedConstraintButWeakTextDoesNotInventBrand() {
        let aurora = CanonicalCatalogEntity(id: "brand-aurora", displayName: "Aurora", kind: .brand)
        let artemis = CanonicalCatalogEntity(id: "brand-artemis", displayName: "Artemis", kind: .brand)
        let block = LanguageUnderstandingBlock(catalogCandidates: [
            .init(value: aurora, displayName: aurora.displayName, aliases: [aurora.displayName]),
            .init(value: artemis, displayName: artemis.displayName, aliases: [artemis.displayName])
        ])
        let recovered = block.parse("Підбери черевики Arora до 7300 гривень")
        #expect([CommandIntent.productSearch, .fashionDiscovery].contains(recovered.intent))
        #expect(recovered.constraints.brand == "Aurora")
        #expect(recovered.entities["catalog_entity_id"] == "brand-aurora")
        #expect(recovered.constraints.maximumPrice == 7_300)

        let weak = block.parse("Підбери черевики невідомої марки")
        #expect(weak.constraints.brand == nil)
        #expect(weak.entities["catalog_entity_id"] == nil)
    }

    @Test func indirectNearbyNeedUsesAWholePropositionInsteadOfWebFallback() {
        let block = LanguageUnderstandingBlock()
        let variants = [
            "Хотілося б випити теплого напою десь поряд",
            "Мені треба перекусити неподалік",
            "Хочу придбати свіжих овочів поблизу"
        ]
        for text in variants {
            let command = block.parse(text)
            #expect(command.intent == .placeSearch, "Selected \(command.intent) for \(text)")
            #expect(command.entities["near_current_location"] == "true")
            #expect(command.entities["proposition_evidence"]?.contains("proximity") == true)
            #expect(command.intent != .webSearch)
            #expect(!command.needsClarification)
        }
    }

    @Test func indirectMovementNeedProducesTypedDestination() {
        let command = LanguageUnderstandingBlock().parse(
            "Мені необхідно потрапити до виставкового павільйону"
        )
        #expect(command.intent == .navigation)
        #expect(command.entities["destination"] == "виставкового павільйону")
        #expect(command.entities["proposition_confidence"].flatMap(Double.init) ?? 0 >= 0.80)
        #expect(command.intent != .webSearch)
        #expect(!command.needsClarification)
    }

    @Test func propositionInferenceCannotOverrideRecognizedPersonalOrSystemFamily() {
        let reminder = LanguageUnderstandingBlock().parse("Мені потрібне нагадування завтра о 8:20")
        #expect([CommandIntent.reminderCreate, .reminderQuery].contains(reminder.intent))
        #expect(reminder.intent != .placeSearch && reminder.intent != .productSearch)

        let settings = LanguageUnderstandingBlock().parse("Хочу відкрити налаштування цього застосунку")
        #expect(settings.intent == .settings)
        #expect(settings.intent != .webSearch)
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

    @Test func closeApplicationCandidatesRenderConciseChoicesThroughReleaseRoot() async throws {
        let language = LanguageUnderstandingBlock(applicationCandidates: [
            .init(value: "nova-blue", displayName: "Nova Blue", aliases: ["Nova"]),
            .init(value: "nova-green", displayName: "Nova Green", aliases: ["Nova"])
        ])
        let model = ProductionAssistantComposition.makeModel(
            languageUnderstanding: language,
            personalSearchSources: [],
            compactResultDuration: .seconds(60)
        )
        model.input = "Запусти Nova"
        model.submit()
        try await wait { if case .actionRequired = model.resultState { return true }; return false }
        guard case let .actionRequired(summary) = model.resultState else {
            Issue.record("Ambiguity did not reach the production choice renderer")
            return
        }
        #expect(summary.choices == ["Nova Blue", "Nova Green"])
        #expect(model.statusText == AppText.value("clarification_needed"))
        #expect({ if case .webHandoff = model.resultState { return false }; return true }())
    }

    @Test func weakApplicationMatchFailsClosedThroughReleaseRoot() async throws {
        let language = LanguageUnderstandingBlock(applicationCandidates: [
            .init(value: "nimbus-studio", displayName: "Nimbus Studio", aliases: ["Nimbus Studio"])
        ])
        let parsed = language.parse("Відкрий панель зоряного пилу")
        #expect(parsed.entities["entity_match_resolution"] == "unresolved")
        #expect(parsed.entities["app"] == nil)
        #expect(parsed.needsClarification)

        let model = ProductionAssistantComposition.makeModel(
            languageUnderstanding: language,
            personalSearchSources: [],
            compactResultDuration: .seconds(60)
        )
        model.input = "Відкрий панель зоряного пилу"
        model.submit()
        try await wait { model.statusText != AppText.value("processing") }
        #expect(model.statusText == AppText.value("clarification_needed"))
        #expect({ if case .webHandoff = model.resultState { return false }; return true }())
    }
}
