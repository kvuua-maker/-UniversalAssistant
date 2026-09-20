import Foundation
import CoreLocation
import Testing
@testable import UniversalAssistant

private final class Build34PhotoLibraryBoundary: PhotoLibrarySearching, @unchecked Sendable {
    private let lock = NSLock()
    let assets: [PhotoAssetReference]
    private var captured: [PhotoSearchCriteria] = []
    init(_ assets: [PhotoAssetReference]) { self.assets = assets }
    func authorization() -> LocalSearchAccess { .permitted }
    func requestAuthorization() async -> LocalSearchAccess { .permitted }
    func search(_ criteria: PhotoSearchCriteria, limit: Int) async -> [PhotoAssetReference] {
        lock.withLock { captured.append(criteria) }
        return Array(assets.prefix(limit))
    }
    func lastCriteria() -> PhotoSearchCriteria? { lock.withLock { captured.last } }
}

private actor Build34PhotoGeocoderBoundary: ManualLocationGeocoding {
    func resolve(_ label: String) async throws -> LocationSample {
        .init(latitude: 48.2915, longitude: 25.9403, horizontalAccuracy: 0,
              timestamp: .now, speed: -1, course: -1, source: .manual)
    }
}

private struct Build34PhotoImageBoundary: PhotoAssetImageLoading {
    let payloads: [String: Data]
    func imageData(localIdentifier: String) async throws -> Data {
        guard let value = payloads[localIdentifier] else { throw CocoaError(.fileNoSuchFile) }
        return value
    }
}

private struct Build34PhotoLabelBoundary: PhotoSemanticLabeling {
    let labels: [String: [PhotoSemanticLabel]]
    func labels(imageData: Data) async throws -> [PhotoSemanticLabel] {
        labels[String(decoding: imageData, as: UTF8.self)] ?? []
    }
}

@MainActor private final class Build34ServiceLocationBoundary: CurrentLocationResolving {
    let value: ValidatedLocation
    init(_ value: ValidatedLocation) { self.value = value }
    func resolveCurrent(for purpose: LocationPurpose) async throws -> ValidatedLocation { value }
}

private actor Build34ServiceGeocoderBoundary: ManualLocationGeocoding {
    let sample: LocationSample
    init(_ sample: LocationSample) { self.sample = sample }
    func resolve(_ label: String) async throws -> LocationSample { sample }
}

private struct Build34ServicePlaceBoundary: PlaceProvider {
    let providerID = "release-mapkit-service-boundary"
    let values: [Place]
    func search(_ query: PlaceQuery) async throws -> [Place] { values }
}

@Suite("Build 34 physical systemic semantic regressions")
struct Build34PhysicalSystemicSemanticTests {
    private let parser = LanguageUnderstandingBlock()

    @Test func temporalSystemFamiliesKeepTypedRolesWithoutCrossFamilyClarification() {
        let timer = parser.parse("Постав таймер на дві хвилини")
        #expect(timer.intent == .deviceAction)
        #expect(timer.entities["system_action"] == "timer")
        #expect(timer.entities["duration_seconds"] == "120")
        #expect(!timer.needsClarification)

        let alarm = parser.parse("Постав будильник на 14:00")
        #expect(alarm.intent == .deviceAction)
        #expect(alarm.entities["system_action"] == "alarm")
        #expect(alarm.entities["hour"] == "14")
        #expect(alarm.entities["minute"] == "00")
        #expect(!alarm.needsClarification)

        let unsupportedAlarmListing = parser.parse("Покажи всі системні будильники")
        #expect(unsupportedAlarmListing.intent == .deviceAction)
        #expect(unsupportedAlarmListing.entities["system_action"] == "unsupported_system_control")
        #expect(unsupportedAlarmListing.intent != .webSearch)
    }

    @Test func calendarCreationOwnsMeetingNounsWhileReminderKeepsReminderNouns() {
        let event = parser.parse("Створи подію завтра о 15:00 зустріч із Катериною")
        #expect(event.intent == .calendarCreate)
        #expect(event.entities["relative_day_offset"] == "1")
        #expect(event.entities["hour"] == "15")
        #expect(event.entities["minute"] == "00")
        #expect(!event.needsClarification)

        let reordered = parser.parse("Запиши в календар на післязавтра о 11:20 демонстрацію макета")
        #expect(reordered.intent == .calendarCreate)
        #expect(!reordered.needsClarification)

        let reminder = parser.parse("Нагадай через сорок секунд перевірити духовку")
        #expect(reminder.intent == .reminderCreate)
        #expect(reminder.entities["relative_interval_seconds"] == "40")
        #expect(!reminder.needsClarification)
    }

    @Test func fileTypeSearchAndOpenRemainDistinctAndSystemFirst() {
        let find = parser.parse("Знайди PDF документи")
        #expect(find.intent == .fileSearch)
        #expect(!find.needsClarification)
        #expect(find.intent != .webSearch)

        let open = parser.parse("Відкрий PDF")
        #expect(open.intent == .fileSearch)
        #expect(!open.needsClarification)
    }

    @Test func fullySpecifiedRestaurantRequestDoesNotAskForSuppliedSlotsAgain() {
        let booking = parser.parse("Забронюй столик для чотирьох гостей завтра о 18:45 у ресторані Липа")
        #expect(booking.intent == .reservation)
        #expect(booking.entities["party_size"] == "4")
        #expect(booking.entities["relative_day_offset"] == "1")
        #expect(booking.entities["hour"] == "18")
        #expect(booking.entities["minute"] == "45")
        #expect(!booking.needsClarification)

        let actuallyAmbiguous = parser.parse("Забронюй столик у ресторані Липа")
        #expect(actuallyAmbiguous.intent == .reservation)
        #expect(actuallyAmbiguous.needsClarification)
    }

    @Test @MainActor func audioRouteCommandsUsePublicSystemPickerAndNeverGenericWeb() async throws {
        let show = parser.parse("Покажи доступні аудіовиходи")
        #expect(show.intent == .deviceAction)
        #expect(show.entities["system_action"] == "audio_route_picker")
        #expect(!show.needsClarification)
        #expect(show.intent != .webSearch)

        let switchRoute = parser.parse("Перемкни відтворення на зовнішній динамік")
        #expect(switchRoute.intent == .deviceAction)
        #expect(switchRoute.entities["system_action"] == "audio_route_picker")
        #expect(!switchRoute.needsClarification)

        let recording = parser.parse("Запиши голосову нотатку")
        #expect(recording.intent == .audioRecord)
        #expect(recording.entities["system_action"] == nil)

        let model = ProductionAssistantComposition.makeModel(
            personalSearchSources: [],
            compactResultDuration: .seconds(60)
        )
        model.input = "Обери аудіопристрій для відтворення"
        model.submit()
        for _ in 0..<100 where model.capabilityPresentation == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.capabilityPresentation == .audioRoutes)
        #expect({ if case .webHandoff = model.resultState { return false }; return true }())
    }

    @Test @MainActor func photoMetadataAllAndSemanticQueriesRemainDistinctAndBounded() async throws {
        let all = parser.parse("Покажи усі світлини")
        #expect(all.intent == .photoSearch)
        #expect(all.entities["photo_query_kind"] == "all")
        let allExecutor = ProductionCanonicalCapabilityExecutor(personalSearchSources: [])
        #expect(try await allExecutor.execute(all) == .presentation(.photoLibrary))

        let absoluteDate = parser.parse("Знайди фотографії за 12 жовтня")
        #expect(absoluteDate.entities["photo_query_kind"] == "metadata")
        #expect(absoluteDate.entities["photo_date_filter"] == "true")
        #expect(absoluteDate.entities["calendar_month"] == "10")
        #expect(absoluteDate.entities["calendar_day"] == "12")

        let relativeDate = parser.parse("Покажи світлини за вчора")
        #expect(relativeDate.entities["photo_query_kind"] == "metadata")
        #expect(relativeDate.entities["relative_day_offset"] == "-1")

        let asset = PhotoAssetReference(localIdentifier: "metadata-photo", creationDate: .now,
                                        coordinate: .init(latitude: 48.2915, longitude: 25.9403), album: nil)
        let library = Build34PhotoLibraryBoundary([asset])
        let executor = ProductionCanonicalCapabilityExecutor(
            photos: library,
            locationResolver: .init(geocoder: Build34PhotoGeocoderBoundary()),
            personalSearchSources: []
        )
        _ = try await executor.execute(relativeDate)
        #expect(library.lastCriteria()?.dateRange != nil)

        let place = parser.parse("Покажи фото з Чернівців")
        #expect(place.intent == .photoSearch, Comment(rawValue: String(describing: place)))
        #expect(place.entities["photo_query_kind"] == "metadata")
        #expect(place.entities["photo_location_query"] == "Чернівці")
        _ = try await executor.execute(place)
        #expect(library.lastCriteria()?.coordinate?.latitude == 48.2915)
        #expect(library.lastCriteria()?.radiusMeters == 50_000)

        let content = parser.parse("Пошукай серед фото велосипед")
        #expect(content.entities["photo_query_kind"] == "semantic")
        #expect(content.entities["photo_location_query"] == nil)
    }

    @Test func multilingualVisionConceptBridgeGeneralizesAcrossInflections() async {
        let assets = [
            PhotoAssetReference(localIdentifier: "pet", creationDate: nil, coordinate: nil, album: nil),
            PhotoAssetReference(localIdentifier: "shore", creationDate: nil, coordinate: nil, album: nil),
            PhotoAssetReference(localIdentifier: "vehicle", creationDate: nil, coordinate: nil, album: nil)
        ]
        let library = Build34PhotoLibraryBoundary(assets)
        let engine = PhotoSemanticSearchEngine(
            library: library,
            loader: Build34PhotoImageBoundary(payloads: [
                "pet": Data("pet".utf8), "shore": Data("shore".utf8), "vehicle": Data("vehicle".utf8)
            ]),
            labeler: Build34PhotoLabelBoundary(labels: [
                "pet": [.init(name: "domestic dog", confidence: 0.91)],
                "shore": [.init(name: "ocean beach", confidence: 0.89)],
                "vehicle": [.init(name: "automobile", confidence: 0.87)]
            ])
        )
        #expect(await engine.search("із собакою", limit: 3).map(\.localIdentifier) == ["pet"])
        #expect(await engine.search("біля моря", limit: 3).map(\.localIdentifier) == ["shore"])
        #expect(await engine.search("автомобілем", limit: 3).map(\.localIdentifier) == ["vehicle"])
        #expect((await engine.search("космічний телескоп", limit: 3)).isEmpty)
    }

    @Test @MainActor func typedCommerceAndRideBoundariesFollowTheSingleCanonicalPolicy() async throws {
        let requests: [(String, Set<CommandIntent>, Bool)] = [
            ("Підбери жіночі туристичні черевики 39 розміру до 4800 гривень", [.productSearch, .fashionDiscovery], true),
            ("Збери кошик для овочевого рагу з доставкою", [.groceryBasket], true),
            ("Порівняй доступні таксі до художнього музею", [.taxiSearch, .taxiCompare], false)
        ]
        for (request, expected, hasOfficialPublicRoute) in requests {
            let command = parser.parse(request)
            #expect(expected.contains(command.intent), "Wrong typed provider family for \(request): \(command.intent)")
            if request.contains("39") { #expect(command.constraints.size == "39") }
            let decision = CanonicalRoutingPolicy().decide(command)
            if request.contains("доставкою") {
                #expect(decision.providerID == "market.prom")
                #expect(decision.allowsMultipleResults == false)
            } else if hasOfficialPublicRoute {
                #expect(decision.lane == .localDiscovery)
                #expect(decision.providerID == "google.maps.url")
                #expect(decision.allowsMultipleResults == false)
            } else {
                #expect(decision.lane == .providerBoundary)
            }
        }
    }

    @Test @MainActor func explicitCarRentalUsesTypedMapKitServiceWhileBareVehicleOrderClarifiesOnce() async throws {
        let explicit = parser.parse("Підбери оренду автомобіля у Львові на завтра")
        #expect(explicit.intent == .serviceSearch)
        #expect(explicit.entities["provider_domain"] == "car_rental")
        #expect(explicit.entities["serviceCategory"] == LocalServiceCategory.carRental.rawValue)
        #expect(explicit.entities["relative_day_offset"] == "1")
        #expect(!explicit.needsClarification)

        let ambiguous = parser.parse("Замов автомобіль")
        #expect(ambiguous.intent == .serviceSearch)
        #expect(ambiguous.entities["clarification_role"] == "vehicle_service")
        #expect(ambiguous.needsClarification)
        #expect(ambiguous.intent != .webSearch)

        let sample = LocationSample(
            latitude: 49.8397, longitude: 24.0297, horizontalAccuracy: 5,
            timestamp: .now, speed: 0, course: 0, source: .manual
        )
        let location = ValidatedLocation(
            sample: sample, quality: .precise,
            isSafeForLocationActions: true, manualLabel: "Львів"
        )
        let place = Place(
            id: "rental-agency", providerID: "mapkit",
            name: "Міська агенція оренди", category: .other,
            latitude: sample.latitude, longitude: sample.longitude,
            address: "Центр міста", officialWebsite: URL(string: "https://rental.example/reserve"),
            source: "MapKit", timestamp: .now, verification: .providerReturned
        )
        var directDestinations: [URL] = []
        let direct = ProductionAssistantComposition.makeModel(
            locationResolver: .init(geocoder: Build34ServiceGeocoderBoundary(sample)),
            placeSearch: .init(providers: [Build34ServicePlaceBoundary(values: [place])]),
            currentLocation: Build34ServiceLocationBoundary(location),
            personalSearchSources: [], compactResultDuration: .seconds(60),
            systemHandoffOpen: { directDestinations.append($0) }
        )
        let directText = "Знайди прокат машини у Львові на післязавтра"
        let document = LanguageUnderstandingBlock.document(directText)
        let tokenForms = document.tokens.reduce(into: Set<String>()) { values, token in
            values.insert(token.normalized)
            values.formUnion(token.morphologyForms)
        }
        #expect(tokenForms.contains { $0.hasPrefix("прокат") }, "No rental role in \(tokenForms)")
        #expect(tokenForms.contains { $0.hasPrefix("машин") }, "No vehicle role in \(tokenForms)")
        #expect(tokenForms.contains { $0.hasPrefix("знайд") }, "No service goal in \(tokenForms)")
        let frame = CanonicalSemanticFrameAnalyzer().analyze(
            original: directText,
            normalized: document.normalizedText,
            morphologyForms: document.tokens.map(\.morphologyForms)
        ).frame
        #expect(frame.source == nil, "Unexpected source role: \(String(describing: frame.source))")
        #expect(frame.contextReference == nil, "Unexpected context role: \(String(describing: frame.contextReference))")
        let directCommand = parser.parse(directText)
        #expect(directCommand.intent == .serviceSearch, "Direct rental intent: \(directCommand)")
        #expect(directCommand.entities["serviceCategory"] == LocalServiceCategory.carRental.rawValue, "Direct rental entities: \(directCommand.entities)")
        #expect(!directCommand.needsClarification, "Direct rental unexpectedly clarified: \(directCommand)")
        direct.input = directText
        direct.submit()
        for _ in 0..<100 {
            if case .placeResults = direct.resultState { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard case let .placeResults(directPlaces) = direct.resultState else {
            Issue.record("Explicit car rental did not reach Release boundary; command=\(directCommand); state=\(direct.resultState); status=\(direct.statusText)")
            return
        }
        #expect(directPlaces.map(\.id) == ["rental-agency"])
        #expect(directDestinations.isEmpty)

        var continuedDestinations: [URL] = []
        let continued = ProductionAssistantComposition.makeModel(
            locationResolver: .init(geocoder: Build34ServiceGeocoderBoundary(sample)),
            placeSearch: .init(providers: [Build34ServicePlaceBoundary(values: [place])]),
            currentLocation: Build34ServiceLocationBoundary(location),
            personalSearchSources: [], compactResultDuration: .seconds(60),
            systemHandoffOpen: { continuedDestinations.append($0) }
        )
        continued.input = "Замов автомобіль"
        continued.submit()
        for _ in 0..<100 {
            if case .actionRequired = continued.resultState { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        continued.resolveActionRequiredChoice("Оренда автомобіля")
        for _ in 0..<100 {
            if case .placeResults = continued.resultState { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard case let .placeResults(continuedPlaces) = continued.resultState else {
            Issue.record("Continued rental request did not return internal places"); return
        }
        #expect(continuedPlaces.map(\.id) == ["rental-agency"])
        #expect(continuedDestinations.isEmpty)
        #expect({ if case .webHandoff = continued.resultState { return false }; return true }())
    }

    @Test @MainActor func photoMetadataAllSemanticAndPDFFindReachTheShippedReleaseRoot() async throws {
        let asset = PhotoAssetReference(
            localIdentifier: "release-metadata-asset", creationDate: .now,
            coordinate: .init(latitude: 49.8397, longitude: 24.0297), album: nil
        )
        let library = Build34PhotoLibraryBoundary([asset])

        let metadata = ProductionAssistantComposition.makeModel(
            photos: library, personalSearchSources: [], compactResultDuration: .seconds(60)
        )
        metadata.input = "Покажи світлини, зроблені вчора"
        metadata.submit()
        for _ in 0..<100 {
            if case .deterministic = metadata.resultState { break }
            if case .failure = metadata.resultState { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect({ if case .deterministic = metadata.resultState { return true }; return false }())
        #expect(metadata.statusText != AppText.value("processing"))

        let all = ProductionAssistantComposition.makeModel(
            photos: library, personalSearchSources: [], compactResultDuration: .seconds(60)
        )
        all.input = "Відобрази всю мою фототеку"
        all.submit()
        for _ in 0..<100 where all.capabilityPresentation == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(all.capabilityPresentation == .photoLibrary)

        let semantic = ProductionAssistantComposition.makeModel(
            photos: library,
            photoSemanticLoader: Build34PhotoImageBoundary(payloads: [asset.localIdentifier: Data("vehicle".utf8)]),
            photoSemanticLabeler: Build34PhotoLabelBoundary(labels: ["vehicle": [.init(name: "automobile", confidence: 0.91)]]),
            personalSearchSources: [], compactResultDuration: .seconds(60)
        )
        semantic.input = "Пошукай у фототеці зображення автомобіля"
        semantic.submit()
        for _ in 0..<100 {
            if case .deterministic = semantic.resultState { break }
            if case .failure = semantic.resultState { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard case let .deterministic(semanticResult) = semantic.resultState else {
            Issue.record("Semantic Photos did not terminate through Release root: \(semantic.resultState)")
            return
        }
        #expect(semanticResult.actions.first?.id == "photos:\(asset.localIdentifier)")

        let pdf = ProductionAssistantComposition.makeModel(
            personalSearchSources: [], compactResultDuration: .seconds(60)
        )
        pdf.input = "Пошукай документи формату PDF"
        pdf.submit()
        for _ in 0..<100 where pdf.capabilityPresentation == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(pdf.capabilityPresentation == .documents)
        #expect({ if case .webHandoff = pdf.resultState { return false }; return true }())
    }
}
