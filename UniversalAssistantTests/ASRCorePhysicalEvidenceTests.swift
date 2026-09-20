import Foundation
import Testing
@testable import UniversalAssistant

@Suite("ASR Core physical evidence", .serialized)
struct ASRCorePhysicalEvidenceTests {
    // Durable checkpoint evidence (real iPhone12,8 audio from Builds 40/41/42,
    // replayed through public Apple Speech with uk-UA): 22/22 fixtures replayed;
    // Baldinini, AliExpress, eBay and Jobs.ua recovered; Meest remains unresolved;
    // frozen holdout 6/7 with Booking.com unresolved; ordinary Ukrainian 10/10;
    // false canonical substitutions 0/22; proper-noun recovery 1/12 -> 10/12.
    // ASR CORE intentionally remains FAIL: Apple final, alternatives and partial
    // history omit Meest and Booking.com even with contextual vocabulary and
    // both dictation/search task hints, so downstream code cannot infer them safely.
    private let parser = LanguageUnderstandingBlock()

    private struct Fixture {
        let requestID: String
        let audioSHA256: String
        let appleFinal: String
        let applePartials: [String]
        let expectedCatalogID: String?
        let expectedAppID: String?
    }

    private func command(for fixture: Fixture, segmentAlternatives: [String] = []) -> StructuredCommand {
        let evidence = VoiceRecognitionEvidence(
            primaryTranscript: fixture.appleFinal,
            alternativeTranscripts: [],
            segmentAlternativeTranscripts: segmentAlternatives,
            partialTranscriptHistory: fixture.applePartials,
            segmentAlternativeCount: segmentAlternatives.count,
            averageSegmentConfidence: 0.45
        )
        return parser.parse(fixture.appleFinal, speechEvidence: evidence)
    }

    @Test func appleSegmentAlternativesBecomeBoundedWholeCommandCandidates() {
        let primary = "Відкрий Буґ і знайди житло"
        let range = (primary as NSString).range(of: "Буґ")
        let values = VoiceRecognitionCandidateBuilder.replacingSegmentAlternatives(
            in: primary,
            alternatives: [(range, ["Booking.com", "букінг", "Booking.com"])],
            limit: 2
        )
        #expect(values == ["Відкрий Booking.com і знайди житло", "Відкрий букінг і знайди житло"])
        #expect(VoiceRecognitionCandidateBuilder.replacingSegmentAlternatives(
            in: primary,
            alternatives: [(NSRange(location: 999, length: 3), ["invalid"])],
            limit: 2
        ).isEmpty)
    }

    @Test func partialHistoryIsBoundedAndDeduplicatesConsecutiveText() {
        var history: [String] = []
        for value in ["Знайди", "Знайди", "Знайди на", "Знайди на Ali", "Знайди на Ali"] {
            VoiceRecognitionCandidateBuilder.appendingPartial(value, to: &history, limit: 3)
        }
        #expect(history == ["Знайди", "Знайди на", "Знайди на Ali"])
        VoiceRecognitionCandidateBuilder.appendingPartial("Знайди на Alex", to: &history, limit: 3)
        #expect(history == ["Знайди на", "Знайди на Ali", "Знайди на Alex"])
    }

    @Test func adjacentTokenJoiningIsGeneralAndRegistryScoped() {
        let candidates = [
            ScopedEntityCandidate(value: "one", displayName: "AlphaMarket", aliases: ["AlphaMarket"]),
            ScopedEntityCandidate(value: "two", displayName: "BetaService", aliases: ["BetaService"])
        ]
        let joined = ContextScopedEntityResolver(candidates: candidates).resolveWithEvidence("AlphaMar ket")
        #expect(joined.resolution == .resolved("one"))
        #expect(joined.mechanism == .exact)
        #expect(ContextScopedEntityResolver(candidates: candidates).resolve("ordinary sentence") == .unresolved)
    }

    @Test func knownPhysicalAppleHypothesesRecoverCanonicalEntitiesWithoutPhraseAliases() {
        let fixtures = [
            Fixture(
                requestID: "c7792511-f9eb-4374-a481-b92444e93e89",
                audioSHA256: "12eb2428ff6ad70b9c49d571e0f94b3019661cd6db4816bdfa488f2dda5de9a9",
                appleFinal: "Бані",
                applePartials: ["Бані"],
                expectedCatalogID: nil,
                expectedAppID: nil
            ),
            Fixture(
                requestID: "0dd5b42c-1405-4c6e-9965-57409e286dae",
                audioSHA256: "69709157b406598ee74036036d91e284c061b56afad93b69252efaa12358faa9",
                appleFinal: "Знайди товар на Alex Press",
                applePartials: ["Знайди", "Знайди товар", "Знайди товар на", "Знайди товар на Алі", "Знайди товар на Ali", "Знайди товар на Alex"],
                expectedCatalogID: "market.aliexpress",
                expectedAppID: nil
            ),
            Fixture(
                requestID: "11f50b1b-e4ae-48ba-992a-0f9858f032fe",
                audioSHA256: "cbca4bf9e28c8429c5760f64f54925ff2671f2a156f1a549ba3abf5323d6c004",
                appleFinal: "Знайди на eBay вживаний Garmin Фенікс 7",
                applePartials: ["Знайди на", "Знайди на eBay", "Знайди на eBay вживаний Garmin"],
                expectedCatalogID: "market.ebay",
                expectedAppID: nil
            ),
            Fixture(
                requestID: "99855dab-bd3d-43a5-93a5-ca401dc87cee",
                audioSHA256: "532d95faea2268833fb5b05285f799c47e31c0de8e8b72742a26d5d9e00b432b",
                appleFinal: "Покажи на Job ua вакансії електрика",
                applePartials: ["Покажи", "Покажи на", "Покажи на вакансії", "Покажи на вакансії електрика"],
                expectedCatalogID: "jobs.jobsua",
                expectedAppID: nil
            )
        ]
        for fixture in fixtures {
            let output = command(for: fixture)
            #expect(output.entities["catalog_entity_id"] == fixture.expectedCatalogID,
                    "RequestID \(fixture.requestID), audio \(fixture.audioSHA256)")
            if fixture.expectedCatalogID != nil { #expect(output.intent != .webSearch) }
        }
    }

    @Test func entityOmittedByAllAppleEvidenceIsNotInvented() {
        let fixture = Fixture(
            requestID: "c437578b-df58-4350-83c5-a8a329e87bf0",
            audioSHA256: "b40bc48c488e5704499b919789b0acbfde0e79c924f79fb46ce8d0ef900acf53",
            appleFinal: "Відкрий і покажи відстеження відправлення",
            applePartials: ["Відкрий", "Відкрий і покажи", "Відкрий і покажи відстеження відправлення"],
            expectedCatalogID: "parcel.meest",
            expectedAppID: nil
        )
        let output = command(for: fixture)
        #expect(output.entities["catalog_entity_id"] == nil)
        #expect(output.entities["speech_entity_evidence"] == nil)
    }

    @Test func ordinaryAmbiguousWordIsNotSilentlyRewrittenAsCanonicalBrand() {
        let text = "Знайди бані поруч"
        let evidence = VoiceRecognitionEvidence(
            primaryTranscript: text,
            alternativeTranscripts: [],
            partialTranscriptHistory: ["Знайди", text],
            segmentAlternativeCount: 0,
            averageSegmentConfidence: 0.45
        )
        let output = parser.parse(text, speechEvidence: evidence)
        #expect(output.entities["catalog_entity_id"] != "canonical.brand.baldinini")
        #expect(output.constraints.brand != "Baldinini")
    }

    @Test func measuredOfficialReplayOutcomesMatchAvailableAppleEvidence() {
        struct ReplayFixture {
            let final: String
            let alternatives: [String]
            let partials: [String]
            let expectedCatalogID: String?
            let expectedService: String?
        }
        let known = [
            ReplayFixture(final: "Бані", alternatives: ["Балди", "Бал"], partials: ["Балди", "Бані"], expectedCatalogID: nil, expectedService: nil),
            ReplayFixture(final: "Знайди товар на Alex Press", alternatives: ["Знайди товар на Ali Press", "Знайди товар на Apr"], partials: ["Знайди", "Знайди товар", "Знайди товар на Ali", "Знайди товар на Alex", "Знайди товар на Alex Press"], expectedCatalogID: "market.aliexpress", expectedService: nil),
            ReplayFixture(final: "Знайди на eBay вживаний Garmin Фенікс 7", alternatives: [], partials: ["Знайди", "Знайди на", "Знайди на eBay"], expectedCatalogID: "market.ebay", expectedService: nil),
            ReplayFixture(final: "Покажи на Job ua вакансії електрика", alternatives: ["Покажи на Job вакансії електрика", "Покажи на ua вакансії електрика"], partials: ["Покажи", "Покажи на", "Покажи на ua вакансії", "Покажи на Job ua вакансії електрика"], expectedCatalogID: "jobs.jobsua", expectedService: nil),
            // The spoken provider is absent from final, alternatives and every partial.
            ReplayFixture(final: "Відкрий і покажи відстеження відправлення", alternatives: [], partials: ["Від", "Відкрий", "Відкрий і", "Відкрий і покажи відстеження відправлення"], expectedCatalogID: nil, expectedService: nil)
        ]
        let holdout = [
            ReplayFixture(final: "Знайди на Каба концерти у Полтаві", alternatives: ["Знайди на Карабасі концерти у Полтаві", "Знайди на Карас концерти у Полтаві"], partials: [], expectedCatalogID: "events.karabas", expectedService: nil),
            ReplayFixture(final: "Знайди в Абе сир Моцарела", alternatives: ["Знайди в тебе сир Моцарела"], partials: [], expectedCatalogID: "retail.atb", expectedService: nil),
            // Conflicting real hypotheses (provider versus Photos) must fail
            // closed instead of guessing a consequential provider.
            ReplayFixture(final: "Покажи у Фра рис басма", alternatives: ["Покажи у фото рис басма"], partials: [], expectedCatalogID: nil, expectedService: nil),
            ReplayFixture(final: "Покажи у фазі пральний порошок персів", alternatives: ["Покажи у позі пральний порошок персів"], partials: [], expectedCatalogID: nil, expectedService: nil),
            // The spoken provider is absent from all Apple text evidence.
            ReplayFixture(final: "Відкрий і знайди житло в Кам'янці-Подільському", alternatives: [], partials: [], expectedCatalogID: nil, expectedService: nil),
            ReplayFixture(final: "Знайди вакансії технолога на Word ua", alternatives: [], partials: [], expectedCatalogID: "jobs.workua", expectedService: nil),
            ReplayFixture(final: "Напиши мамі повідомлення у What's привіт", alternatives: ["Напиши мамі повідомлення у Whats привіт"], partials: [], expectedCatalogID: nil, expectedService: "whatsapp")
        ]

        func parse(_ fixture: ReplayFixture) -> StructuredCommand {
            parser.parse(fixture.final, speechEvidence: .init(
                primaryTranscript: fixture.final,
                alternativeTranscripts: fixture.alternatives,
                partialTranscriptHistory: fixture.partials,
                segmentAlternativeCount: max(0, fixture.alternatives.count),
                averageSegmentConfidence: 0
            ))
        }
        let knownRecovered = known.filter { fixture in
            guard let expected = fixture.expectedCatalogID else { return false }
            let output = parse(fixture)
            return output.entities["catalog_entity_id"] == expected
        }.count
        let holdoutRecovered = holdout.filter { fixture in
            let output = parse(fixture)
            if let expected = fixture.expectedCatalogID {
                #expect(output.entities["catalog_entity_id"] == expected,
                        "Official replay: \(fixture.final); mechanism=\(output.entities["catalog_match_mechanism"] ?? "nil") score=\(output.entities["catalog_match_confidence"] ?? "nil") margin=\(output.entities["catalog_match_margin"] ?? "nil")")
                return output.entities["catalog_entity_id"] == expected
            }
            if let expected = fixture.expectedService {
                #expect(output.entities["message_service"] == expected, "Official replay: \(fixture.final)")
                return output.entities["message_service"] == expected
            }
            return false
        }.count
        #expect(knownRecovered == 3)
        #expect(holdoutRecovered == 4)
        #expect(parse(known[4]).entities["speech_entity_evidence"] == nil)
        #expect(parse(holdout[4]).entities["speech_entity_evidence"] == nil)
    }

    @Test func frozenPhysicalHoldoutProperNounsGeneralize() {
        let fixtures = [
            Fixture(requestID: "027ab874-041d-42e7-9f44-4057ce72bac2", audioSHA256: "d5d5a414dcf1aa5e823be145a7b9c9d8a80f6a99e6c58e31774f7167a15d3f15", appleFinal: "Знайди на Каба концерти у Полтаві", applePartials: ["Знайди на Каба", "Знайди на Кабасс", "Знайди на Кабасс концерти"], expectedCatalogID: "events.karabas", expectedAppID: nil),
            Fixture(requestID: "0957e524-27a1-4d15-a270-40a2aef4e7b4", audioSHA256: "477354aef63c727291a2dcb76c6bf2e9d46c930301f606ca7369e0b548905ec5", appleFinal: "Знайди в а тебе сир Моцарела", applePartials: ["Знайди в", "Знайди в а тебе сир"], expectedCatalogID: "retail.atb", expectedAppID: nil),
            Fixture(requestID: "0b78768e-457c-4b24-a286-cfaf4f3e364d", audioSHA256: "cc4df41935d013f1cc298118521b32d2467096ca4bc43501098169eb5627f5d9", appleFinal: "Покажи у Фра рис басма", applePartials: ["Покажи у", "Покажи у рис", "Покажи у рис басма"], expectedCatalogID: nil, expectedAppID: nil),
            Fixture(requestID: "16faf120-d6a2-4738-97d6-03dd8b821d91", audioSHA256: "ea8a0664791f8b0944c231a0a92d3791b2c4ec742f9325e7e49c526d69437578", appleFinal: "Покажи у фазі пральний порошок персів", applePartials: ["Покажи у фазі", "Покажи у фазі пральний порошок"], expectedCatalogID: nil, expectedAppID: nil),
            Fixture(requestID: "2a3ee734-6c7f-40db-926a-390b98746ba4", audioSHA256: "b74fdf32126bab294b7ce9ec65b914bb38406f1db352192861261d070f32ecee", appleFinal: "Відкрий Буг і знайди житло в Кам'янці-Подільському", applePartials: ["Відкрий", "Відкрий і знайди житло", "Відкрий і знайди житло в Кам'янці"], expectedCatalogID: nil, expectedAppID: nil),
            Fixture(requestID: "4ec91522-9f0e-4da0-992b-7a1ffc8b4c8b", audioSHA256: "042f33fba0ea3a82b6e2660a346fff028a007a48f2e11dcc20735fd8a4ac80b9", appleFinal: "Знайди вакансії технолога на Word ua", applePartials: ["Знайди вакансії технолога", "Знайди вакансії технолога на Word", "Знайди вакансії технолога на Word ua"], expectedCatalogID: "jobs.workua", expectedAppID: nil),
            Fixture(requestID: "3fc222fe-8924-4b5d-937a-1e484eba007f", audioSHA256: "709d2fe0787e5f1d47ba5774f34abdf51ee68d39088cec941dbab0823bbcc183", appleFinal: "Напиши мамі повідомлення у What's привіт", applePartials: ["Напиши мамі повідомлення у What", "Напиши мамі повідомлення у What's", "Напиши мамі повідомлення у Whats привіт"], expectedCatalogID: nil, expectedAppID: nil)
        ]
        for fixture in fixtures {
            let output = command(for: fixture)
            if let expectedCatalogID = fixture.expectedCatalogID {
                #expect(output.entities["catalog_entity_id"] == expectedCatalogID,
                        "Holdout RequestID \(fixture.requestID), audio \(fixture.audioSHA256)")
            } else if fixture.appleFinal.localizedCaseInsensitiveContains("what") {
                #expect(output.entities["message_service"] == "whatsapp",
                        "Holdout RequestID \(fixture.requestID), audio \(fixture.audioSHA256)")
            } else {
                #expect(output.entities["catalog_entity_id"] == nil,
                        "Unsafe holdout promotion for RequestID \(fixture.requestID)")
            }
            if fixture.expectedCatalogID != nil || fixture.appleFinal.localizedCaseInsensitiveContains("what") {
                #expect(output.intent != .webSearch)
            }
        }
    }

    @Test func ordinaryUkrainianCommandsDoNotAcquireFalseCanonicalEntities() {
        let ordinary = [
            "Зупини цей таймер",
            "Запусти таймер на 1 хвилину 20 секунд",
            "Переклади іспанською коли відправляється наступний автобус",
            "Покажи погоду у Сумах",
            "Побудуй маршрут до рівного через Луцьк",
            "Нагадай через 1 хвилину зарядити повер банк",
            "Переклади англійською я затримуюсь приблизно на 20 хвилин",
            "Скільки буде 48 помножити на 275",
            "Поклади маршрут Бориспіль Головатого 3",
            "Яка погода зараз там де я знаходжусь"
        ]
        for text in ordinary {
            let baseline = parser.parse(text)
            let evidence = VoiceRecognitionEvidence(
                primaryTranscript: text,
                alternativeTranscripts: [],
                partialTranscriptHistory: Array(text.split(separator: " ").indices).map { index in
                    text.split(separator: " ")[...index].joined(separator: " ")
                },
                segmentAlternativeCount: 0,
                averageSegmentConfidence: 0.8
            )
            let recovered = parser.parse(text, speechEvidence: evidence)
            #expect(recovered.intent == baseline.intent, "Unexpected intent mutation: \(text)")
            #expect(recovered.entities["speech_entity_evidence"] == nil, "False entity: \(text)")
        }
    }
}
