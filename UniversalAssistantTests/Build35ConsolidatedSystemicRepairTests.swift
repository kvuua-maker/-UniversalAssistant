import AVFoundation
import CoreLocation
import Foundation
import Speech
import Testing
@testable import UniversalAssistant

private struct Build35ContactAuthorization: ContactAuthorizing {
    let state: ContactAuthorizationState
    func currentStatus() -> ContactAuthorizationState { state }
    func requestAccess() async throws -> Bool { state == .authorized || state == .limited }
}

private actor Build35ContactQuery: ContactQuerying {
    let predicate: [ContactCandidate]
    let accessible: [ContactCandidate]

    init(predicate: [ContactCandidate], accessible: [ContactCandidate]) {
        self.predicate = predicate
        self.accessible = accessible
    }

    func contacts(matching name: String, timeout: Duration) async throws -> [ContactCandidate] {
        predicate
    }

    func contact(identifier: String, timeout: Duration) async throws -> ContactCandidate? {
        accessible.first { $0.identifier == identifier }
    }

    func accessibleContacts(limit: Int, timeout: Duration) async throws -> [ContactCandidate] {
        Array(accessible.prefix(limit))
    }
}

private actor Build35DelayedPhotoLoader: PhotoAssetImageLoading {
    private var observedCancellation = false
    private var started = false

    func imageData(localIdentifier: String) async throws -> Data {
        started = true
        do {
            try await Task.sleep(for: .seconds(5))
            return Data(localIdentifier.utf8)
        } catch {
            observedCancellation = true
            throw error
        }
    }

    func wasCancelled() -> Bool { observedCancellation }
    func wasStarted() -> Bool { started }
}

private struct Build35PhotoLibrary: PhotoLibrarySearching {
    let assets: [PhotoAssetReference]
    func authorization() -> LocalSearchAccess { .permitted }
    func requestAuthorization() async -> LocalSearchAccess { .permitted }
    func search(_ criteria: PhotoSearchCriteria, limit: Int) async -> [PhotoAssetReference] {
        Array(assets.prefix(limit))
    }
}

private struct Build35PhotoLabeler: PhotoSemanticLabeling {
    func labels(imageData: Data) async throws -> [PhotoSemanticLabel] {
        [.init(name: "building", confidence: 0.9)]
    }
}

private actor Build35ExplicitLocationGeocoder: ManualLocationGeocoding {
    let sample: LocationSample
    init(sample: LocationSample) {
        self.sample = sample
    }

    func resolve(_ label: String) async throws -> LocationSample { sample }
}

@MainActor
private final class Build35CurrentLocation: CurrentLocationResolving {
    let value: ValidatedLocation
    init(_ value: ValidatedLocation) { self.value = value }
    func resolveCurrent(for purpose: LocationPurpose) async throws -> ValidatedLocation { value }
}

private struct Build35PlaceProvider: PlaceProvider {
    let providerID = "build35-location-boundary"
    let places: [Place]
    func search(_ query: PlaceQuery) async throws -> [Place] { places }
}

@Suite("Build 35 consolidated systemic repair")
struct Build35ConsolidatedSystemicRepairTests {
    private let language = LanguageUnderstandingBlock()

    @Test func speechConfigurationReservesCanonicalEntitiesUnderLargeDynamicVocabulary() {
        let dynamic = (0..<90).map { "Контакт \($0)" }
        let configuration = VoiceRecognitionRequestConfiguration(additionalVocabulary: dynamic)
        let request = SFSpeechAudioBufferRecognitionRequest()
        configuration.apply(to: request)

        #expect(request.taskHint == .dictation)
        #expect(configuration.contextualVocabulary.count <= 100)
        #expect(configuration.contextualVocabulary.first == "Контакт 0")
        let folded = Set(configuration.contextualVocabulary.map {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        })
        for phrase in VoiceRecognitionRequestConfiguration.canonicalEntityVocabulary {
            let key = phrase.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            #expect(folded.contains(key), "Canonical Speech entity was evicted: \(phrase)")
        }
    }

    @Test func adaptiveSpeechActivityAcceptsQuietNaturalInput() {
        let tracker = VoiceSpeechActivityTracker(minimumRMS: 0.002, minimumAdaptiveRMS: 0.0004)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 128)!
        buffer.frameLength = 128
        guard let samples = buffer.floatChannelData?[0] else {
            Issue.record("Expected Float32 samples")
            return
        }
        for index in 0..<Int(buffer.frameLength) { samples[index] = 0.0007 }
        tracker.record(buffer)
        #expect(tracker.hasRecentVoiceActivity(within: 1.25))
    }

    @Test func noisyProperNounsRecoverOnlyInsideTheirVerifiedDomain() {
        let brands = ContextScopedEntityResolver(candidates: [
            ScopedEntityCandidate(value: "brand-a", displayName: "Baldinini", aliases: ["Baldinini"]),
            ScopedEntityCandidate(value: "brand-b", displayName: "Puma", aliases: ["Puma"]),
            ScopedEntityCandidate(value: "brand-c", displayName: "Nike", aliases: ["Nike"])
        ])
        #expect(brands.resolve("Балді") == .resolved("brand-a"))
        #expect(brands.resolve("Бані") == .resolved("brand-a"))

        let applications = ContextScopedEntityResolver(candidates: [
            ScopedEntityCandidate(value: "communication-a", displayName: "WhatsApp", aliases: ["WhatsApp"]),
            ScopedEntityCandidate(value: "communication-b", displayName: "WeChat", aliases: ["WeChat"])
        ])
        #expect(applications.resolve("Whats") == .resolved("communication-a"))
        #expect(applications.resolve("невідома") == .unresolved)
    }

    @Test func contactInflectionsRankAgainstWholeAuthorizedDomainAndNeverPickShortLabel() async throws {
        let unrelated = ContactCandidate(
            identifier: "unrelated", displayName: "AM",
            phoneNumbers: ["+380000000001"], aliases: ["AM"]
        )
        let mother = ContactCandidate(
            identifier: "mother", displayName: "Марія Садова",
            phoneNumbers: ["+380000000002"], aliases: ["Мама"]
        )
        let friend = ContactCandidate(
            identifier: "friend", displayName: "Олександр Гнатюк",
            phoneNumbers: ["+380000000003"], aliases: ["Сашко"]
        )
        let resolver = LocalContactResolver(
            authorization: Build35ContactAuthorization(state: .authorized),
            query: Build35ContactQuery(
                predicate: [unrelated],
                accessible: [unrelated, mother, friend]
            ),
            queryTimeout: .seconds(1)
        )

        #expect(try await resolver.resolve(name: "мамі") == .resolved(mother))
        #expect(try await resolver.resolve(name: "Сашку") == .resolved(friend))
        #expect(try await resolver.resolve(name: "невідомій людині") == .notFound)
    }

    @Test func contactExactAmbiguityRemainsASelectionInsteadOfArbitraryExecution() async throws {
        let first = ContactCandidate(
            identifier: "one", displayName: "Олена Романюк",
            phoneNumbers: ["+380000000004"], aliases: ["Олена"]
        )
        let second = ContactCandidate(
            identifier: "two", displayName: "Олена Сидоренко",
            phoneNumbers: ["+380000000005"], aliases: ["Олена"]
        )
        let resolver = LocalContactResolver(
            authorization: Build35ContactAuthorization(state: .limited),
            query: Build35ContactQuery(predicate: [first], accessible: [first, second]),
            queryTimeout: .seconds(1)
        )
        guard case let .ambiguous(values) = try await resolver.resolve(name: "Олені") else {
            Issue.record("Expected safe contact ambiguity")
            return
        }
        #expect(Set(values.map(\.identifier)) == ["one", "two"])
    }

    @Test func communicationServiceAndPersonRolesRemainIndependent() {
        let email = language.parse("Надішли Дарині Коваль електронного листа")
        #expect(email.intent == .messageCompose)
        #expect(email.entities["message_service"] == "email")
        #expect(email.entities["recipient"] == "Дарині Коваль")
        #expect(!email.needsClarification)

        let telegram = language.parse("Напиши Романові у Telegram")
        #expect(telegram.intent == .messageCompose)
        #expect(telegram.entities["message_service"] == "telegram")
        #expect(telegram.entities["recipient"] == "Романові")

        let generic = language.parse("Надішли повідомлення Ірині")
        #expect(generic.intent == .messageCompose)
        #expect(generic.entities["message_service"] == "messages")
        #expect(generic.entities["recipient"] == "Ірині")
    }

    @Test func translationTargetClauseIsRemovedFromSourceAtEitherBoundary() {
        let trailing = language.parse("Переклади Я повернуся завтра ввечері на англійську мову")
        #expect(trailing.intent == .translation)
        #expect(trailing.entities["target_language"] == "en")
        #expect(trailing.entities["source_text"] == "Я повернуся завтра ввечері")

        let leading = language.parse("Переклади німецькою: Потяг прибуває вранці")
        #expect(leading.entities["target_language"] == "de")
        #expect(leading.entities["source_text"] == "Потяг прибуває вранці")
    }

    @Test func typedRolesPreemptKeywordCollisionsAcrossUtilityCurrencyTranslationAndEvents() {
        let division = language.parse("Поділи 18432 на 48")
        #expect(division.intent == .localUtility)
        #expect(division.intent != .calendarQuery)

        let currency = language.parse("Переведи €275 у польські злоті")
        #expect(currency.intent == .currencyConversion)
        #expect(currency.intent != .navigation)

        let translated = language.parse("Переклади польською: Резервація столика підтверджена")
        #expect(translated.intent == .translation)
        #expect(translated.entities["target_language"] == "pl")
        #expect(translated.entities["source_text"] == "Резервація столика підтверджена")
        #expect(translated.intent != .reservation)

        let publicEvent = language.parse("Знайди квитки на театральну подію")
        #expect(publicEvent.intent == .ticketSearch)
        #expect(publicEvent.intent != .calendarQuery)
    }

    @Test func speechAlternativesMayRepairCompleteTypedRolesButCannotInventPrivilegedIntent() {
        let utilityEvidence = VoiceRecognitionEvidence(
            primaryTranscript: "Поділи тисячу на сорок",
            alternativeTranscripts: ["Поділи 1000 на 40", "Видали подію на сорок"],
            segmentAlternativeCount: 3,
            averageSegmentConfidence: 0.41
        )
        let utility = language.parse(utilityEvidence.primaryTranscript, speechEvidence: utilityEvidence)
        #expect(utility.intent == .localUtility)
        #expect(utility.intent != .calendarDelete)

        let appBlock = LanguageUnderstandingBlock(applicationCandidates: [
            .init(value: "team-radio", displayName: "Team Radio", aliases: ["TeamRadio"])
        ])
        let appEvidence = VoiceRecognitionEvidence(
            primaryTranscript: "Відкрий Team Rad",
            alternativeTranscripts: ["Відкрий Team Radio", "Вимкни Bluetooth"],
            segmentAlternativeCount: 3,
            averageSegmentConfidence: 0.38
        )
        let app = appBlock.parse(appEvidence.primaryTranscript, speechEvidence: appEvidence)
        #expect(app.intent == .open)
        #expect(app.entities["app"] == "team-radio")
        #expect(app.intent != .deviceAction)
    }

    @Test func scopedEntityRecoveryUsesBoundedSpansAndFailsClosedOutsideItsDomain() {
        let block = LanguageUnderstandingBlock(
            applicationCandidates: [
                .init(value: "field-notes", displayName: "Field Notes", aliases: ["FieldNotes"]),
                .init(value: "city-radio", displayName: "City Radio", aliases: ["CityRadio"])
            ],
            serviceCandidates: [
                .init(value: "secure-wire", displayName: "Secure Wire", aliases: ["SecureWire"]),
                .init(value: "team-chat", displayName: "Team Chat", aliases: ["TeamChat"])
            ]
        )
        let application = block.parse("Запусти Field No")
        #expect(application.intent == .open)
        #expect(application.entities["app"] == "field-notes")
        #expect(!application.needsClarification)

        let message = block.parse("Надішли Олені у Secure Wi")
        #expect(message.intent == .messageCompose)
        #expect(message.entities["message_service"] == "secure-wire")
        #expect(message.entities["recipient"] == "Олені")

        let unrelated = block.parse("Покажи погоду у місті")
        #expect(unrelated.entities["app"] == nil)
        #expect(unrelated.entities["message_service"] == nil)
    }

    @Test func contactDataFilesAndNavigationUseTheirTypedSystemDomains() {
        let contact = language.parse("Покажи номер телефону Дарини Левченко")
        #expect(contact.intent == .contactLookup)
        #expect(contact.entities["contact"] == "Дарини Левченко")
        #expect(contact.intent != .webSearch)

        let files = language.parse("Відкрий папку завантажень")
        #expect(files.intent == .fileSearch)
        #expect(files.intent != .open)
        #expect(!files.needsClarification)

        let route = language.parse("Побудуй маршрут до площі Ринок")
        #expect(route.intent == .navigation)
        #expect(route.entities["destination"] == "площі Ринок")
        #expect(route.intent != .webSearch)
    }

    @Test func scopedClockReconstructionCoversCalendarAndReservationWithoutGlobalThresholdChanges() {
        let calendar = language.parse("Створи зустріч завтра о дев'ятнадцятій 0 0")
        #expect(calendar.intent == .calendarCreate)
        #expect(calendar.entities["hour"] == "19")
        #expect(calendar.entities["minute"] == "00")
        #expect(!calendar.needsClarification)

        let reservation = language.parse("Зарезервуй столик для чотирьох гостей післязавтра о двадцятій 30")
        #expect(reservation.intent == .reservation)
        #expect(reservation.entities["hour"] == "20")
        #expect(reservation.entities["minute"] == "30")
        #expect(!reservation.needsClarification)
    }

    @Test func localDeviceStorageUsesCompositionalSystemFirstSemantics() {
        for input in [
            "Покажи доступний простір цього пристрою",
            "Скільки залишилось місця в пам'яті телефону",
            "Available storage on this iPhone"
        ] {
            let command = language.parse(input)
            #expect(command.intent == .deviceAction, "Wrong family for \(input)")
            #expect(command.entities["system_action"] == "storage")
            #expect(command.intent != .webSearch)
            #expect(!command.needsClarification)
        }
    }

    @Test func completeCalendarAndReservationSlotsDoNotClarify() {
        let calendar = language.parse("Додай у календар післязавтра о 09:35 огляд проєкту з Наталею")
        #expect(calendar.intent == .calendarCreate)
        #expect(calendar.entities["relative_day_offset"] == "2")
        #expect(calendar.entities["hour"] == "09")
        #expect(calendar.entities["minute"] == "35")
        #expect(!calendar.needsClarification)

        let reservation = language.parse("Зарезервуй столик для трьох гостей завтра о 20:10 у ресторані Верба")
        #expect(reservation.intent == .reservation)
        #expect(reservation.entities["party_size"] == "3")
        #expect(reservation.entities["relative_day_offset"] == "1")
        #expect(reservation.entities["hour"] == "20")
        #expect(reservation.entities["minute"] == "10")
        #expect(!reservation.needsClarification)
    }

    @Test func semanticPhotoTimeoutCancelsOutstandingLocalAssetWork() async {
        let loader = Build35DelayedPhotoLoader()
        let asset = PhotoAssetReference(localIdentifier: "slow", creationDate: nil, coordinate: nil, album: nil)
        let engine = PhotoSemanticSearchEngine(
            library: Build35PhotoLibrary(assets: [asset]),
            loader: loader,
            labeler: Build35PhotoLabeler()
        )
        let clock = ContinuousClock()
        let start = clock.now
        #expect((await engine.search("будівля", timeout: .milliseconds(50))).isEmpty)
        #expect(start.duration(to: clock.now) < .seconds(1))
        let workStarted = await loader.wasStarted()
        let workCancelled = await loader.wasCancelled()
        #expect(!workStarted || workCancelled)
    }

    @Test @MainActor func explicitServiceLocationFiltersProviderDefaultResults() async throws {
        let explicitSample = LocationSample(
            latitude: 49.5535, longitude: 25.5948, horizontalAccuracy: 5,
            timestamp: .now, speed: 0, course: 0, source: .manual
        )
        let currentSample = LocationSample(
            latitude: 34.0522, longitude: -118.2437, horizontalAccuracy: 5,
            timestamp: .now, speed: 0, course: 0, source: .device
        )
        let current = ValidatedLocation(
            sample: currentSample, quality: .precise,
            isSafeForLocationActions: true, manualLabel: nil
        )
        let nearby = Place(
            id: "near", providerID: "mapkit-near", name: "Місцева оренда",
            category: .other, latitude: 49.56, longitude: 25.60,
            officialWebsite: URL(string: "https://rental.example/ternopil"),
            source: "MapKit", timestamp: .now, verification: .providerReturned
        )
        let far = Place(
            id: "far", providerID: "mapkit-far", name: "Airport rental",
            category: .other, latitude: 33.94, longitude: -118.40,
            officialWebsite: URL(string: "https://rental.example/airport"),
            source: "MapKit", timestamp: .now, verification: .providerReturned
        )
        let explicit = ValidatedLocation(
            sample: explicitSample, quality: .approximate,
            isSafeForLocationActions: true, manualLabel: "Тернопіль"
        )
        let placeSearch = PlaceSearchEngine(providers: [Build35PlaceProvider(places: [far, nearby])])
        let providerResponse = try await placeSearch.search(.init(
            text: "car rental", category: .other, location: explicit,
            radiusMeters: 10_000, limit: 12
        ))
        #expect(providerResponse.places.count == 2)
        let bounded = PlaceProximityOrdering()
            .nearestFirst(providerResponse.places, from: explicit)
            .filter { ($0.distanceMeters ?? .greatestFiniteMagnitude) <= 10_000 }
        #expect(bounded.map(\.id) == ["near"])

        let executor = ProductionCanonicalCapabilityExecutor(
            locationResolver: .init(geocoder: Build35ExplicitLocationGeocoder(sample: explicitSample)),
            placeSearch: placeSearch,
            currentLocation: Build35CurrentLocation(current),
            personalSearchSources: []
        )
        let command = language.parse("Знайди прокат автомобіля в Тернополі на завтра")
        #expect(command.intent == .serviceSearch)
        guard case let .result(result) = try await executor.execute(command) else {
            Issue.record("Expected bounded local-service result")
            return
        }
        #expect(result.facts.map { $0.id } == ["near"])
    }
}
