import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Build 42 canonical partner and physical-root repair", .serialized)
@MainActor
struct Build42CanonicalPartnerRepairTests {
    @Test func auditedPartnerPoliciesAreCompleteUniqueZeroCostAndTruthful() {
        let policies = CanonicalPartnerPolicyRegistry.records
        #expect(policies.count == 64)
        #expect(Set(policies.map(\.providerID)).count == policies.count)
        #expect(policies.filter { $0.decision == .affiliateActive }.isEmpty)
        #expect(policies.filter { $0.decision == .affiliateReadyOwnerAction }.count == 36)
        #expect(policies.filter { $0.decision == .functionalNoAffiliateProgram }.count == 12)
        #expect(policies.filter { $0.decision == .unknown }.count == 15)
        #expect(policies.filter { $0.decision == .unsupported }.count == 1)
        #expect(policies.allSatisfy { $0.costToUniversalAssistant == 0 })
        #expect(policies.filter { $0.decision == .affiliateReadyOwnerAction }
            .allSatisfy { $0.requiresOwnerAction })
        for provider in OfficialPublicProviderHandoffRegistry.records {
            #expect(CanonicalPartnerPolicyRegistry.policy(for: provider.id) != nil)
        }
    }

    @Test func attributionAddsOnlyVerifiedAllowlistedFieldsAndKeepsExactQuery() throws {
        let requestID = UUID(uuidString: "A5C16E63-FD7C-4660-AE1B-84523735E99B")!
        let exact = URL(string: "https://www.ebay.com/sch/i.html?_nkw=Seiko%20automatic&discount=owner")!
        let configuration = AffiliateRoutingConfiguration(
            providerID: "market.ebay",
            allowedHosts: ["www.ebay.com"],
            allowedParameterNames: ["campid", "customid"],
            parameterValues: ["campid": "approved-campaign"],
            officiallyVerifiedAt: .now,
            requestSubIDParameterName: "customid"
        )
        let handoff = try AffiliatePurchaseRouter().route(
            providerID: "market.ebay",
            exactDestination: exact,
            configuration: configuration,
            requestID: requestID
        )
        let values = Dictionary(uniqueKeysWithValues:
            (URLComponents(url: handoff.destination, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                .compactMap { item in item.value.map { (item.name, $0) } }
        )
        #expect(values["_nkw"] == "Seiko automatic")
        #expect(values["discount"] == "owner")
        #expect(values["campid"] == "approved-campaign")
        #expect(values["customid"] == requestID.uuidString.lowercased())
        #expect(handoff.attribution == .outboundParametersApplied)
    }

    @Test func officialRedirectPreservesExactDestinationAndRejectsUnapprovedFields() throws {
        let exact = URL(string: "https://shop.example/search?q=trail+shoes")!
        let redirect = AffiliateRedirectConfiguration(
            baseURL: URL(string: "https://partner.example/click")!,
            destinationParameterName: "url"
        )
        let valid = AffiliateRoutingConfiguration(
            providerID: "store.example",
            allowedHosts: ["shop.example"],
            allowedParameterNames: ["publisher", "subid", "url"],
            parameterValues: ["publisher": "approved"],
            officiallyVerifiedAt: .now,
            requestSubIDParameterName: "subid",
            redirect: redirect
        )
        let requestID = UUID()
        let routed = try AffiliatePurchaseRouter().route(
            providerID: "store.example", exactDestination: exact,
            configuration: valid, requestID: requestID
        )
        let destination = URLComponents(url: routed.destination, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "url" })?.value
        #expect(destination == exact.absoluteString)

        let invalid = AffiliateRoutingConfiguration(
            providerID: "store.example",
            allowedHosts: ["shop.example"],
            allowedParameterNames: ["publisher"],
            parameterValues: ["publisher": "approved"],
            officiallyVerifiedAt: .now,
            redirect: redirect
        )
        do {
            _ = try AffiliatePurchaseRouter().route(
                providerID: "store.example", exactDestination: exact,
                configuration: invalid, requestID: requestID
            )
            Issue.record("Expected invalid redirect rejection")
        } catch let error as AffiliateRoutingError {
            if error != .invalidRedirect {
                Issue.record("Unexpected redirect error: \(error)")
            }
        }
    }

    @Test func explicitProviderRolesOverrideLexicalCollisionsWithoutPhraseAliases() {
        let parser = LanguageUnderstandingBlock()
        let cases: [(String, String, CommandIntent)] = [
            ("Знайди на eBay годинник Seiko", "market.ebay", .productSearch),
            ("Покажи на Ali Express бездротові навушники", "market.aliexpress", .productSearch),
            ("Знайди вакансію Swift на Work ua", "jobs.workua", .productSearch),
            ("Покажи відправлення через Meest", "parcel.meest", .parcelTrack),
            ("Знайди помешкання у Booking.com", "lodging.booking", .hotelSearch)
        ]
        for (text, providerID, intent) in cases {
            let command = parser.parse(text)
            #expect(command.entities["catalog_entity_id"] == providerID)
            #expect(command.intent == intent)
            #expect(command.entities["query"]?.isEmpty == false)
            #expect(!command.needsClarification)
            #expect(command.intent != .webSearch)
        }
        let personal = parser.parse("Подзвони контакту на ім’я Ebay")
        #expect(personal.intent != .productSearch)
    }

    @Test func properNounRecoveryUsesCandidatesAndSpeechAlternatives() {
        let parser = LanguageUnderstandingBlock()
        let brand = parser.parse("Знайди чоловіче взуття Балдініні")
        #expect(brand.constraints.brand == "Baldinini")
        #expect(brand.intent == .productSearch)

        let evidence = VoiceRecognitionEvidence(
            primaryTranscript: "Знайди зарядку на Ali Press",
            alternativeTranscripts: ["Знайди зарядку на Ali Express"],
            segmentAlternativeCount: 2,
            averageSegmentConfidence: 0.48
        )
        let recovered = parser.parse(evidence.primaryTranscript, speechEvidence: evidence)
        #expect(recovered.entities["catalog_entity_id"] == "market.aliexpress")
        #expect(recovered.intent == .productSearch)
    }

    @Test func speechContextKeepsEveryProductionProviderAndRemainsAppleBounded() {
        let vocabulary = VoiceRecognitionRequestConfiguration(
            additionalVocabulary: (0..<80).map { "Контакт \($0)" }
        ).contextualVocabulary
        #expect(vocabulary.count <= 100)
        #expect(vocabulary.contains("Baldinini"))
        let master = Set(VoiceRecognitionRequestConfiguration.masterVocabulary)
        for provider in OfficialPublicProviderHandoffRegistry.records {
            #expect(master.contains(provider.displayName))
        }
    }

    @Test func productionExecutorAppliesInjectedAttributionAndStableRequestSubID() async throws {
        let command = StructuredCommand(
            id: UUID(uuidString: "E284C67A-A120-4E4F-A1B8-2989912B0AB6")!,
            originalText: "Знайди на eBay Seiko",
            normalizedText: "знайди на ebay seiko",
            language: .uk,
            intent: .productSearch,
            entities: ["provider": "eBay", "product": "Seiko"]
        )
        let configuration = AffiliateRoutingConfiguration(
            providerID: "market.ebay",
            allowedHosts: ["www.ebay.com"],
            allowedParameterNames: ["campid", "customid"],
            parameterValues: ["campid": "approved-campaign"],
            officiallyVerifiedAt: .now,
            requestSubIDParameterName: "customid"
        )
        let executor = ProductionCanonicalCapabilityExecutor(
            personalSearchSources: [],
            affiliateConfigurations: ["market.ebay": configuration]
        )
        guard case let .handoff(handoff) = try await executor.execute(command) else {
            Issue.record("Expected provider handoff")
            return
        }
        let items = URLComponents(url: handoff.destination, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.first(where: { $0.name == "_nkw" })?.value == "Seiko")
        #expect(items.first(where: { $0.name == "campid" })?.value == "approved-campaign")
        #expect(items.first(where: { $0.name == "customid" })?.value == command.id.uuidString.lowercased())
        #expect(handoff.kind == .provider)
        #expect(!handoff.requiresExplicitUserActivation)
    }

    @Test func build40SemanticCollisionFamiliesUseTypedRoles() {
        let parser = LanguageUnderstandingBlock()
        let cases: [(String, CommandIntent)] = [
            ("Відкрий камеру для фотографування", .cameraCapture),
            ("Покажи прогноз сильного вітру на вихідні", .weather),
            ("Знайди в галереї останнє відео", .photoSearch),
            ("Покажи скріншоти за вчора", .photoSearch),
            ("Знайди на Prom акумуляторний шуруповерт", .productSearch),
            ("Знайди на eBay ноутбук з 32 гігабайтами пам'яті", .productSearch)
        ]
        for (text, intent) in cases {
            let command = parser.parse(text)
            #expect(command.intent == intent, "Unexpected intent for: \(text)")
            #expect(command.intent != .webSearch)
        }
        #expect(parser.parse("Скільки вільного місця на iPhone").intent == .deviceAction)
        #expect(parser.parse("Який заряд батареї").intent == .deviceAction)
    }

    @Test func officialRateAndCompoundDurationUseCanonicalLocalExecutors() throws {
        let rate = try #require(FXConversionRequestParser().parse("Покажи офіційний курс долара НБУ"))
        #expect(rate.amount == 1)
        #expect(rate.source == "USD")
        #expect(rate.destination == "UAH")

        let targetFirst = try #require(FXConversionRequestParser().parse("Скільки гривень буде за 430 євро"))
        #expect(targetFirst.amount == 430)
        #expect(targetFirst.source == "EUR")
        #expect(targetFirst.destination == "UAH")

        let conventional = try #require(FXConversionRequestParser().parse("275 EUR to PLN"))
        #expect(conventional.source == "EUR")
        #expect(conventional.destination == "PLN")

        let text = "Переведи 2 години 45 хвилин у хвилини"
        let command = LanguageUnderstandingBlock().parse(text)
        #expect(command.intent == .localUtility)
        let result = try LocalUtilityEngine().execute(
            text,
            locale: Locale(identifier: "uk_UA"),
            timeZone: TimeZone(secondsFromGMT: 0)!,
            now: Date(timeIntervalSince1970: 0)
        )
        #expect(result == "165 min")
    }

    @Test func typedTranslationAndLodgingRolesResolveWithoutGlobalThresholdChanges() throws {
        let spokenTranslation = try #require(CanonicalTranslationRoles.analyze("Скажи італійською: добрий вечір"))
        #expect(spokenTranslation.targetLanguage == "it")
        #expect(spokenTranslation.sourceText == "добрий вечір")

        let parser = LanguageUnderstandingBlock()
        for text in ["Покажи номер для двох людей", "Підбери кімнату для трьох гостей"] {
            let command = parser.parse(text)
            #expect(command.intent == .hotelSearch, "Unexpected intent for: \(text)")
            #expect(command.entities["provider_domain"] == "lodging")
            #expect(!command.needsClarification)
        }
        #expect(parser.parse("Знайди номер телефону контакту").intent != .hotelSearch)
    }

    @Test func providerMorphologyAndSpeechAlternativesRecoverRegistryEntitiesGenerally() {
        let parser = LanguageUnderstandingBlock()
        let inflected = [
            ("Покажи сеанси у Планеті Кіно", "cinema.planetakino"),
            ("Відстеж посилку Укрпоштою", "parcel.ukrposhta")
        ]
        for (text, providerID) in inflected {
            let command = parser.parse(text)
            #expect(command.entities["catalog_entity_id"] == providerID)
            #expect(command.intent != .webSearch)
            #expect(!command.needsClarification)
        }

        let evidence = VoiceRecognitionEvidence(
            primaryTranscript: "Знайди авто через гетьман кар",
            alternativeTranscripts: ["Знайди авто через Getmancar"],
            segmentAlternativeCount: 2,
            averageSegmentConfidence: 0.42
        )
        let recovered = parser.parse(evidence.primaryTranscript, speechEvidence: evidence)
        #expect(recovered.entities["catalog_entity_id"] == "rental.getmancar")
        #expect(recovered.intent != .webSearch)
    }
}
