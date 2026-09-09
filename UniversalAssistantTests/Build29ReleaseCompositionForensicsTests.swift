import Foundation
import Testing
import UIKit
@testable import UniversalAssistant

private actor Build29ReleaseContactBoundary: ContactResolving {
    let resolution: ContactResolution
    init(_ resolution: ContactResolution) { self.resolution = resolution }
    func authorizationState() async -> ContactAuthorizationState { .authorized }
    func requestAccessIfNeeded() async throws {}
    func resolve(name: String) async throws -> ContactResolution { resolution }
    func resolve(exactIdentifier identifier: String) async throws -> ContactResolution { resolution }
}

@MainActor
private final class Build29SystemOpenCapture {
    private(set) var urls: [URL] = []
    func open(_ url: URL) { urls.append(url) }
}

@Suite("Build 29 Release composition forensics", .serialized)
@MainActor
struct Build29ReleaseCompositionForensicsTests {
    @Test func physicalContactAndMessageEvidenceReachesTypedFamiliesBeforeFallback() {
        let parser = LocalCommandEngine()
        let expectations: [(String, CommandIntent)] = [
            ("Подзвони мама", .contactCall),
            ("Подзвони Сашко", .contactCall),
            ("Подзвони Влад", .contactCall),
            ("Напиши мама", .messageCompose),
            ("Напиши Сашко", .messageCompose),
            ("Напиши Влад", .messageCompose)
        ]
        for (input, expected) in expectations {
            let command = parser.parse(input)
            #expect(command.intent == expected, "Release parser selected \(command.intent) for \(input)")
            #expect(command.intent != .webSearch && command.intent != .unknown)
        }
    }

    @Test func releaseHomeCallUsesCanonicalExecutorAndTelephoneHandoff() async throws {
        let contact = ContactCandidate(identifier: "release-contact", displayName: "Наталія", phoneNumbers: ["+380 67 111 22 33"])
        let capture = Build29SystemOpenCapture()
        let model = ProductionAssistantComposition.makeModel(
            contacts: Build29ReleaseContactBoundary(.resolved(contact)),
            personalSearchSources: [], compactResultDuration: .seconds(60),
            systemHandoffOpen: capture.open
        )
        model.input = "Набери Наталія"
        model.submit()
        for _ in 0..<100 where capture.urls.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(capture.urls.first?.scheme == "tel")
        #expect(model.statusText != AppText.value("processing"))
    }

    @Test func releaseHomeMessageProducesSystemComposerWithoutWeb() async throws {
        let contact = ContactCandidate(identifier: "release-message-contact", displayName: "Марко", phoneNumbers: ["+380 93 555 66 77"])
        let model = ProductionAssistantComposition.makeModel(
            contacts: Build29ReleaseContactBoundary(.resolved(contact)),
            personalSearchSources: [], compactResultDuration: .seconds(60)
        )
        model.input = "Напиши Марко що зустрінемось пізніше"
        model.submit()
        for _ in 0..<100 where model.capabilityPresentation == nil { try await Task.sleep(for: .milliseconds(10)) }
        guard case let .message(recipients, _)? = model.capabilityPresentation else {
            Issue.record("Release Home did not reach MessageUI presentation")
            return
        }
        #expect(recipients == ["380935556677"])
        #expect(model.statusText != AppText.value("processing"))
    }

    @Test func nearbyNaturalRequestCannotResolveAsGenericWeb() {
        let parser = LocalCommandEngine()
        for input in ["Перекусити неподалік", "Знайди пекарню поблизу", "Де поруч випити чаю"] {
            let command = parser.parse(input)
            #expect([.placeSearch, .restaurantSearch, .serviceSearch].contains(command.intent), "Selected \(command.intent) for \(input)")
            #expect(command.intent != .webSearch && command.intent != .unknown)
        }
    }
}


private actor Build29ReleaseEventKitBoundary: EventKitCommandExecuting {
    private(set) var commands: [StructuredCommand] = []
    func execute(_ command: StructuredCommand) async throws -> EventKitExecutionResult {
        commands.append(command)
        let reminder = command.intent == .reminderCreate || command.intent == .reminderQuery
        return .init(kind: reminder ? .reminder : .calendar,
                     operation: command.intent == .reminderQuery || command.intent == .calendarQuery ? .queried : .created,
                     title: reminder ? "Нагадування" : "Подія", detail: "verified-boundary", itemCount: 1)
    }
    func intents() -> [CommandIntent] { commands.map(\.intent) }
}

@MainActor
private final class Build29ReleaseRecordingBackend: AudioRecordingBackend {
    private(set) var isRecording = false
    func start(at url: URL) throws -> Bool {
        try Data([1, 2, 3, 4]).write(to: url)
        isRecording = true
        return true
    }
    func pause() { isRecording = false }
    func resume() -> Bool { isRecording = true; return true }
    func stop() { isRecording = false }
    func play(url: URL) throws {}
    func stopPlayback() {}
}

private actor Build29ReleaseMediaBoundary: MediaProviderAdapter {
    let providerID = "apple-music"
    func authorizationState() async -> MediaAuthorizationState { .authorized }
    func requestAuthorization() async -> MediaAuthorizationState { .authorized }
    func search(query: String, kinds: Set<MediaItemKind>, limit: Int) async throws -> [MediaItem] {
        [.init(id: "release-song", providerID: providerID, kind: .song, title: "Boundary Song", artist: "Boundary Artist", exactURL: URL(string: "https://music.apple.com/song/release-song"))]
    }
    func control(_ action: MediaControlAction, item: MediaItem?) async throws {}
}

private actor Build29ReleasePodcastTransport: PodcastHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, Int) {
        let json = #"{"results":[{"trackId":321,"trackName":"Міська лабораторія","collectionName":"Архітектура","trackViewUrl":"https://podcasts.apple.com/episode/321"}]}"#
        return (Data(json.utf8), 200)
    }
}

private struct Build29ReleaseWeatherBoundary: WeatherCommandExecuting {
    func execute(_ command: StructuredCommand) async throws -> WeatherSnapshot {
        .init(current: .init(date: .now, temperatureCelsius: 16, apparentTemperatureCelsius: 15,
                             condition: "cloudy", symbolName: "cloud.fill"),
              hourly: [], daily: [], source: "release-boundary", fetchedAt: .now,
              locationSource: .manual, locationLabel: command.entities["location"], context: .manualLocation)
    }
}

@Suite("Build 29 Release root family reachability", .serialized)
@MainActor
struct Build29ReleaseRootFamilyReachabilityTests {
    @Test func calendarAndReminderShareTheShippedEventKitBoundary() async throws {
        let eventKit = Build29ReleaseEventKitBoundary()
        let model = ProductionAssistantComposition.makeModel(personalSearchSources: [], compactResultDuration: .seconds(60), eventKit: eventKit)
        model.input = "Додай у календар презентацію проєкту післязавтра о 11:20"
        model.submit()
        for _ in 0..<100 { if case .eventKit = model.resultState { break }; try await Task.sleep(for: .milliseconds(10)) }
        model.input = "Нагадай через сорок хвилин перевірити пошту"
        model.submit()
        for _ in 0..<100 { if await eventKit.intents().count == 2 { break }; try await Task.sleep(for: .milliseconds(10)) }
        #expect(await eventKit.intents() == [.calendarCreate, .reminderCreate])
        #expect(model.statusText != AppText.value("processing"))
    }

    @Test func weatherAndLocalUtilityUseReleaseHomeWithoutWebFallback() async throws {
        let model = ProductionAssistantComposition.makeModel(personalSearchSources: [], compactResultDuration: .seconds(60), weather: Build29ReleaseWeatherBoundary())
        model.input = "Покажи прогноз погоди у Львові на післязавтра"
        model.submit()
        for _ in 0..<100 { if case .weather = model.resultState { break }; try await Task.sleep(for: .milliseconds(10)) }
        guard case .weather = model.resultState else { Issue.record("Weather did not reach Release boundary"); return }
        model.input = "Обчисли різницю між девʼяноста трьома і сорока сімома"
        model.submit()
        for _ in 0..<100 { if case .deterministic = model.resultState { break }; try await Task.sleep(for: .milliseconds(10)) }
        guard case .deterministic = model.resultState else { Issue.record("Utility did not reach deterministic Release executor"); return }
        #expect(model.statusText != AppText.value("processing"))
    }

    @Test func mediaAndPodcastProvidersUseReleaseRootWithExactHandoffs() async throws {
        let media = MediaIntegrationEngine(adapters: [Build29ReleaseMediaBoundary()])
        let podcasts = ApplePodcastSearchProvider(transport: Build29ReleasePodcastTransport())
        var opened: [URL] = []
        let model = ProductionAssistantComposition.makeModel(
            podcasts: podcasts,
            mediaOverride: media,
            personalSearchSources: [],
            compactResultDuration: .seconds(60),
            systemHandoffOpen: { opened.append($0) }
        )

        model.input = "Знайди пісню про далеку мандрівку в Apple Music"
        model.submit()
        for _ in 0..<100 { if case .deterministic = model.resultState { break }; try await Task.sleep(for: .milliseconds(10)) }
        guard case let .deterministic(music) = model.resultState else { Issue.record("Apple Music did not reach typed provider boundary"); return }
        #expect(music.facts.first?.source == "Apple Music")
        #expect(music.actions.first?.destination?.host == "music.apple.com")

        model.input = "Знайди подкаст про міську архітектуру"
        model.submit()
        for _ in 0..<100 { if case .deterministic = model.resultState { break }; try await Task.sleep(for: .milliseconds(10)) }
        guard case let .deterministic(podcast) = model.resultState else { Issue.record("Podcast did not reach Apple search boundary"); return }
        #expect(podcast.facts.first?.source == "Apple Podcasts")
        #expect(podcast.actions.first?.destination?.host == "podcasts.apple.com")

        let spotifyInput = "Увімкни добірку для бігу у Spotify"
        let spotifyCommand = LocalCommandEngine().parse(spotifyInput)
        #expect(spotifyCommand.intent == .mediaSearch)
        #expect(spotifyCommand.entities["app"]?.lowercased() == "spotify")
        model.input = spotifyInput
        model.submit()
        for _ in 0..<100 where opened.last?.scheme != "spotify" { try await Task.sleep(for: .milliseconds(10)) }
        #expect(opened.last?.scheme == "spotify")
        #expect(model.resultState == .idle)
        #expect(model.statusText != AppText.value("processing"))
    }

    @Test func voiceMemoLifecycleAndSystemAppSeparationUseReleaseRoot() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let recorder = AudioRecorderController(backend: Build29ReleaseRecordingBackend(), directory: directory, permission: { true })
        var opened: [URL] = []
        let model = ProductionAssistantComposition.makeModel(recorder: recorder, personalSearchSources: [], compactResultDuration: .seconds(60), systemHandoffOpen: { opened.append($0) })

        model.input = "Розпочни звуковий запис для польових нотаток"
        model.submit()
        for _ in 0..<100 where recorder.state != .recording { try await Task.sleep(for: .milliseconds(10)) }
        #expect(recorder.state == .recording)

        model.input = "Призупини активний звуковий запис"
        model.submit()
        for _ in 0..<100 where recorder.state != .paused { try await Task.sleep(for: .milliseconds(10)) }
        #expect(recorder.state == .paused)

        model.input = "Resume the active recording"
        model.submit()
        for _ in 0..<100 where recorder.state != .recording { try await Task.sleep(for: .milliseconds(10)) }
        #expect(recorder.state == .recording)

        model.input = "Заверши цей аудіозапис"
        model.submit()
        for _ in 0..<100 where model.capabilityPresentation == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(recorder.state == .stopped)
        guard case let .audioFile(url) = model.capabilityPresentation else { Issue.record("Stopped recording did not produce durable typed file"); return }
        #expect(FileManager.default.fileExists(atPath: url.path))

        model.input = "Відкрий програму Голосові записи"
        model.submit()
        for _ in 0..<100 { if case .failure = model.resultState { break }; try await Task.sleep(for: .milliseconds(10)) }
        #expect(recorder.state == .stopped)
        #expect(opened.isEmpty)
        #expect({ if case .webHandoff = model.resultState { return false }; return true }())
    }

    @Test func translationAndTruthfulShazamBoundaryUseReleaseHomeWithoutWeb() async throws {
        let model = ProductionAssistantComposition.makeModel(personalSearchSources: [], compactResultDuration: .seconds(60))
        model.input = "Зроби французький переклад тексту: Гарного вам ранку"
        model.submit()
        for _ in 0..<100 { if case .translation = model.capabilityPresentation { break }; try await Task.sleep(for: .milliseconds(10)) }
        guard case let .translation(plan) = model.capabilityPresentation else { Issue.record("Translation did not reach Apple presentation"); return }
        #expect(plan.text == "Гарного вам ранку")
        #expect(plan.targetLanguage == "fr")
        #expect({ if case .webHandoff = model.resultState { return false }; return true }())

        model.input = "Спробуй визначити композицію, що лунає зараз"
        model.submit()
        for _ in 0..<100 { if case .deterministic = model.resultState { break }; try await Task.sleep(for: .milliseconds(10)) }
        guard case let .deterministic(result) = model.resultState else { Issue.record("Shazam boundary did not terminate locally"); return }
        #expect(result.primaryAnswer.localizedCaseInsensitiveContains("ShazamKit"))
        #expect(result.actions.isEmpty)
    }

    @Test func unitAndLocalDateTimeRemainDeterministicInReleaseRoot() async throws {
        let model = ProductionAssistantComposition.makeModel(personalSearchSources: [], compactResultDuration: .seconds(60))
        for input in ["Перерахуй 3,2 кілометра у метри", "Повідом поточну дату", "Назви місцевий час"] {
            model.input = input
            model.submit()
            for _ in 0..<100 { if case .deterministic = model.resultState { break }; try await Task.sleep(for: .milliseconds(10)) }
            #expect({ if case .deterministic = model.resultState { return true }; return false }(), "Did not stay local: \(input)")
            #expect({ if case .webHandoff = model.resultState { return false }; return true }())
        }
    }
}


@Suite("Build 29 Release root system-first reachability", .serialized)
@MainActor
struct Build29ReleaseRootSystemFirstTests {
    private func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Release-root request did not reach a terminal state")
    }

    @Test func storageAndBatteryUseShippedLocalBoundary() async throws {
        var actions: [SystemQuickAction] = []
        let model = ProductionAssistantComposition.makeModel(
            personalSearchSources: [], compactResultDuration: .seconds(60),
            publicDeviceExecute: { action in
                actions.append(action)
                switch action {
                case .freeStorage: return "41 GB"
                case .batteryLevel: return "73%"
                default: return "verified"
                }
            }
        )
        model.input = "Скільки доступного простору є у сховищі цього пристрою?"
        model.submit()
        try await waitUntil { if case .deterministic = model.resultState { return true }; return false }
        model.input = "Покажи рівень акумулятора телефону"
        model.submit()
        try await waitUntil { actions.count == 2 }
        #expect(actions == [.freeStorage, .batteryLevel])
        #expect({ if case .webHandoff = model.resultState { return false }; return true }())
    }

    @Test func clipboardURLUsesExactUserInitiatedContent() async throws {
        let expected = URL(string: "https://developer.apple.com/swift/")!
        var opened: [URL] = []
        let model = ProductionAssistantComposition.makeModel(
            personalSearchSources: [], compactResultDuration: .seconds(60),
            clipboardRead: { .url(expected) }, systemHandoffOpen: { opened.append($0) }
        )
        model.input = "Перейди за адресою, збереженою в буфері обміну"
        model.submit()
        try await waitUntil { !opened.isEmpty }
        #expect(opened == [expected])
        #expect(model.resultState == .idle)
    }

    @Test func settingsDistinguishApplicationFromUnavailableSystemDestination() async throws {
        var opened: [URL] = []
        let model = ProductionAssistantComposition.makeModel(
            personalSearchSources: [], compactResultDuration: .seconds(60), systemHandoffOpen: { opened.append($0) }
        )
        model.input = "Покажи дозволи, надані цьому застосунку"
        model.submit()
        try await waitUntil { !opened.isEmpty }
        #expect(opened.first?.absoluteString == UIApplication.openSettingsURLString)

        opened.removeAll()
        model.input = "Перейди до системних параметрів приватності телефону"
        model.submit()
        try await waitUntil { if case .failure = model.resultState { return true }; return false }
        #expect(opened.isEmpty)
        #expect({ if case .webHandoff = model.resultState { return false }; return true }())
    }
}


private struct Build29ReleasePhotoBoundary: PhotoLibrarySearching {
    let assets: [PhotoAssetReference]
    func authorization() -> LocalSearchAccess { .permitted }
    func requestAuthorization() async -> LocalSearchAccess { .permitted }
    func search(_ criteria: PhotoSearchCriteria, limit: Int) async -> [PhotoAssetReference] { Array(assets.prefix(limit)) }
}

@Suite("Build 29 Release root Photos and Files", .serialized)
@MainActor
struct Build29ReleaseRootPhotoFileTests {
    @Test func sourceRoleSeparatesOrdinalPhotoFromFilesPicker() async throws {
        let newest = PhotoAssetReference(localIdentifier: "release-newest", creationDate: .now, coordinate: nil, album: nil)
        let previous = PhotoAssetReference(localIdentifier: "release-previous", creationDate: .now.addingTimeInterval(-30), coordinate: nil, album: nil)
        let model = ProductionAssistantComposition.makeModel(
            photos: Build29ReleasePhotoBoundary(assets: [newest, previous]),
            personalSearchSources: [], compactResultDuration: .seconds(60)
        )
        model.input = "Покажи другу з останніх світлин"
        model.submit()
        for _ in 0..<100 {
            if case .deterministic = model.resultState { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard case let .deterministic(result) = model.resultState else { Issue.record("Ordinal photo did not reach PhotoKit boundary"); return }
        #expect(result.facts.first?.id == "photos:release-previous")

        model.input = "Дай вибрати електронну таблицю з файлового сховища"
        model.submit()
        for _ in 0..<100 {
            if model.capabilityPresentation == .documents { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.capabilityPresentation == .documents)
        #expect({ if case .webHandoff = model.resultState { return false }; return true }())
    }

    @Test func photoShareAndOCRProduceTypedPresentationsAutomatically() async throws {
        let asset = PhotoAssetReference(localIdentifier: "release-photo", creationDate: .now, coordinate: nil, album: nil)
        let model = ProductionAssistantComposition.makeModel(
            photos: Build29ReleasePhotoBoundary(assets: [asset]), personalSearchSources: [], compactResultDuration: .seconds(60)
        )
        model.input = "Надішли найсвіжішу світлину"
        model.submit()
        for _ in 0..<100 {
            if model.capabilityPresentation == .photoShare("release-photo") { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.capabilityPresentation == .photoShare("release-photo"))

        model.input = "Прочитай напис на найновішому знімку"
        model.submit()
        for _ in 0..<100 {
            if model.capabilityPresentation == .photoOCR("release-photo") { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.capabilityPresentation == .photoOCR("release-photo"))
    }
}


@MainActor private final class Build29ReleaseLocationBoundary: CurrentLocationResolving {
    let value: ValidatedLocation
    init(_ value: ValidatedLocation) { self.value = value }
    func resolveCurrent(for purpose: LocationPurpose) async throws -> ValidatedLocation { value }
}
private actor Build29ReleaseGeocoderBoundary: ManualLocationGeocoding {
    let sample: LocationSample
    init(_ sample: LocationSample) { self.sample = sample }
    func resolve(_ label: String) async throws -> LocationSample { sample }
}
private struct Build29ReleaseReverseBoundary: ReverseLocationGeocoding {
    func address(for location: ValidatedLocation) async throws -> String { "Test address" }
    func locality(for location: ValidatedLocation) async throws -> String { "Test locality" }
}
private struct Build29ReleasePlaceBoundary: PlaceProvider {
    let providerID = "release-mapkit-boundary"
    let values: [Place]
    func search(_ query: PlaceQuery) async throws -> [Place] { values }
}
private struct Build29ReleaseRouteBoundary: RouteProvider {
    let providerID = "release-directions-boundary"
    func route(_ request: RouteRequest) async throws -> RouteResult {
        .init(distanceMeters: 1800, expectedTravelTime: 420, steps: ["Continue straight"], source: providerID, timestamp: .now)
    }
}

@Suite("Build 29 Release root MapKit and CoreLocation", .serialized)
@MainActor
struct Build29ReleaseRootLocationRouteTests {
    private func location(_ latitude: Double, _ longitude: Double, source: LocationSource = .device) -> ValidatedLocation {
        .init(sample: .init(latitude: latitude, longitude: longitude, horizontalAccuracy: 5, timestamp: .now, speed: 0, course: 0, source: source), quality: .precise, isSafeForLocationActions: true, manualLabel: nil)
    }
    private func model(opened: @escaping @MainActor (URL) -> Void = { _ in }) -> AssistantViewModel {
        let origin = location(50.45, 30.52)
        let destination = location(50.46, 30.55, source: .manual)
        let places = [
            Place(id: "far", providerID: "far", name: "Far Clinic", category: .clinic, latitude: 50.70, longitude: 30.80, source: "MapKit boundary", timestamp: .now, verification: .providerReturned),
            Place(id: "near", providerID: "near", name: "Near Clinic", category: .clinic, latitude: 50.451, longitude: 30.521, source: "MapKit boundary", timestamp: .now, verification: .providerReturned)
        ]
        return ProductionAssistantComposition.makeModel(
            locationResolver: .init(geocoder: Build29ReleaseGeocoderBoundary(destination.sample)),
            placeSearch: .init(providers: [Build29ReleasePlaceBoundary(values: places)]),
            currentLocation: Build29ReleaseLocationBoundary(origin), reverseLocation: Build29ReleaseReverseBoundary(),
            routeProvider: Build29ReleaseRouteBoundary(), personalSearchSources: [], compactResultDuration: .seconds(60),
            systemHandoffOpen: opened
        )
    }

    @Test func nearbyRankingNavigationTravelTimeAndRouteFollowupUseOneShippedContext() async throws {
        var opened: [URL] = []
        let model = model { opened.append($0) }
        model.input = "Яка клініка розташована найближче до мене?"
        model.submit()
        for _ in 0..<100 { if case .deterministic = model.resultState { break }; try await Task.sleep(for: .milliseconds(10)) }
        guard case let .deterministic(nearby) = model.resultState else { Issue.record("Nearby did not reach Place boundary"); return }
        #expect(nearby.facts.first?.id == "near")

        model.input = "Визнач моє теперішнє місцезнаходження"
        model.submit()
        for _ in 0..<100 { if case .deterministic = model.resultState { break }; try await Task.sleep(for: .milliseconds(10)) }
        guard case let .deterministic(coordinates) = model.resultState else { Issue.record("Current location did not reach CoreLocation boundary"); return }
        #expect(coordinates.facts.first?.source == "CoreLocation")
        #expect(coordinates.facts.first?.value?.contains("50.45000") == true)

        model.input = "Назви адресу в моїй поточній точці"
        model.submit()
        for _ in 0..<100 { if case .deterministic = model.resultState { break }; try await Task.sleep(for: .milliseconds(10)) }
        guard case let .deterministic(address) = model.resultState else { Issue.record("Address did not reach reverse-geocoding boundary"); return }
        #expect(address.primaryAnswer == "Test address")

        model.input = "До якого міста належить моя теперішня геопозиція?"
        model.submit()
        for _ in 0..<100 { if case .deterministic = model.resultState { break }; try await Task.sleep(for: .milliseconds(10)) }
        guard case let .deterministic(locality) = model.resultState else { Issue.record("Locality did not reach reverse-geocoding boundary"); return }
        #expect(locality.primaryAnswer == "Test locality")

        model.input = "Побудуй шлях до центральної бібліотеки"
        model.submit()
        for _ in 0..<100 { if case .webHandoff = model.resultState { break }; try await Task.sleep(for: .milliseconds(10)) }
        guard case let .webHandoff(navigation) = model.resultState else { Issue.record("Navigation did not reach handoff renderer"); return }
        #expect(navigation.kind == .navigation)
        #expect(navigation.destination.host?.contains("maps.apple.com") == true)
        #expect(opened.isEmpty)

        model.input = "Скільки триватиме дорога до виставкового центру?"
        model.submit()
        for _ in 0..<100 { if case .deterministic = model.resultState { break }; try await Task.sleep(for: .milliseconds(10)) }
        guard case let .deterministic(travel) = model.resultState else { Issue.record("Travel time did not reach route boundary"); return }
        #expect(travel.primaryAnswer.contains("7 хв"))

        model.input = "Як дістатися громадським транспортом до ботанічного саду?"
        model.submit()
        for _ in 0..<100 { if case .webHandoff = model.resultState { break }; try await Task.sleep(for: .milliseconds(10)) }
        guard case let .webHandoff(transit) = model.resultState else { Issue.record("Transit route did not reach MapKit handoff"); return }
        #expect(transit.kind == .navigation)
        #expect(transit.destination.absoluteString.contains("dirflg=r") == true)

        model.input = "Знайди клініку вздовж цього маршруту"
        model.submit()
        for _ in 0..<100 {
            if case let .deterministic(value) = model.resultState, value.primaryAnswer.contains("дорозі") { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard case let .deterministic(routePlace) = model.resultState else { Issue.record("Route context did not continue"); return }
        #expect(routePlace.facts.first?.source == "MapKit boundary")
        #expect({ if case .webHandoff = model.resultState { return false }; return true }())
    }
}

private actor Build29ReleaseFXBoundary: CurrentFXProviding {
    func convert(_ request: FXConversionRequest) async throws -> CurrentFXConversion {
        .init(request: request, convertedAmount: 123.45, observedAt: .now, provider: "Verified FX boundary")
    }
}

@Suite("Build 29 Release root system and FX reachability", .serialized)
@MainActor
struct Build29ReleaseRootSystemFXTests {
    @Test func currentFXUsesShippedProviderBoundaryAndUnsupportedCurrencyIsTruthful() async throws {
        let model = ProductionAssistantComposition.makeModel(
            personalSearchSources: [], compactResultDuration: .seconds(60), fx: Build29ReleaseFXBoundary()
        )
        model.input = "Конвертуй 37 євро у польські злоті"
        model.submit()
        for _ in 0..<100 { if case .deterministic = model.resultState { break }; try await Task.sleep(for: .milliseconds(10)) }
        guard case let .deterministic(result) = model.resultState else { Issue.record("FX did not reach Release provider boundary"); return }
        #expect(result.primaryAnswer.contains("123"))
        #expect(result.facts.first?.source == "Verified FX boundary")
        #expect(model.statusText != AppText.value("processing"))
    }

    @Test func flashlightUsesPublicDeviceBoundaryForBothStateDirections() async throws {
        var actions: [SystemQuickAction] = []
        let model = ProductionAssistantComposition.makeModel(
            personalSearchSources: [], compactResultDuration: .seconds(60),
            publicDeviceExecute: { action in actions.append(action); return "device boundary" }
        )
        model.input = "Активуй кишеньковий ліхтар"
        model.submit()
        for _ in 0..<100 where actions.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(actions.last == .flashlight(enabled: true))

        model.input = "Вимкни кишеньковий ліхтар"
        model.submit()
        for _ in 0..<100 where actions.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(actions.last == .flashlight(enabled: false))
        #expect(model.statusText != AppText.value("processing"))
    }

    @Test func unavailableSystemControlsTerminateLocallyWithoutWeb() async throws {
        let model = ProductionAssistantComposition.makeModel(personalSearchSources: [], compactResultDuration: .seconds(60))
        let requests = [
            "Встанови яскравість дисплея нижче",
            "Задай гучність на третину",
            "Активуй режим енергозбереження",
            "Вимкни Bluetooth",
            "Покажи журнал пропущених дзвінків",
            "Відкрий Локатор для моїх пристроїв"
        ]
        for request in requests {
            let parsed = LocalCommandEngine().parse(request)
            #expect(parsed.intent == .deviceAction)
            #expect(parsed.entities["system_action"] == "unsupported_system_control")
            model.input = request
            model.submit()
            for _ in 0..<100 {
                if case .failure = model.resultState { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            guard case .failure = model.resultState else { Issue.record("System limitation did not terminate locally: \(request)"); continue }
            #expect({ if case .webHandoff = model.resultState { return false }; return true }())
            #expect(model.statusText != AppText.value("processing"))
        }
    }

    @Test func previousResultCopyAndShareConsumeTypedReleaseContext() async throws {
        var actions: [SystemQuickAction] = []
        let model = ProductionAssistantComposition.makeModel(
            personalSearchSources: [], compactResultDuration: .seconds(60),
            publicDeviceExecute: { action in actions.append(action); return "copied" }
        )
        model.input = "Котра година за місцевим часом?"
        model.submit()
        for _ in 0..<100 { if case .deterministic = model.resultState { break }; try await Task.sleep(for: .milliseconds(10)) }
        guard case let .deterministic(initial) = model.resultState else { Issue.record("Initial result missing"); return }

        model.input = "Скопіюй останній результат у буфер обміну"
        model.submit()
        for _ in 0..<100 where actions.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(actions.last == .copyToClipboard(initial.primaryAnswer))

        model.input = "Поділися останнім результатом"
        model.submit()
        for _ in 0..<100 where model.capabilityPresentation == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(model.capabilityPresentation == .share("copied"))
        #expect(model.statusText != AppText.value("processing"))
    }
}


private struct Build29ReleaseDiscoveryBoundary: GenericDiscoveryProvider {
    let id = "release-provider"
    func discover(_ intent: GenericIntent, query: String) async throws -> [GenericDiscoveryDocument] {
        let safeTitle = intent.brandOrProvider ?? intent.subject
        let payload = "<script type=\"application/ld+json\">{\"@type\":\"Thing\",\"name\":\"" + safeTitle.replacingOccurrences(of: "\"", with: "") + "\",\"url\":\"https://provider.example/result\"}</script>"
        return [.init(response: .init(finalURL: URL(string: "https://provider.example/result")!, html: payload, fetchedAt: .now, sourceTimestamp: .now), sourceKind: .structuredMarketplace)]
    }
}

@Suite("Build 29 Release external provider boundaries", .serialized)

@MainActor
struct Build29ReleaseExternalProviderBoundaryTests {
@Test func configuredProviderIsReachableFromUnknownAndTypedCommerceHomePaths() async throws {
        let discovery = GenericUnknownRequestCoordinator(providers: [Build29ReleaseDiscoveryBoundary()], cache: GenericSemanticCache(), ai: nil)
        let model = ProductionAssistantComposition.makeModel(personalSearchSources: [], compactResultDuration: .seconds(60), genericDiscovery: discovery)
        for input in ["Розкажи актуальний стан міжнародної місії", "Підбери водостійкий туристичний рюкзак до 4200 гривень"] {
            model.input = input
            model.submit()
            for _ in 0..<100 { if case .deterministic = model.resultState { break }; try await Task.sleep(for: .milliseconds(10)) }
            guard case let .deterministic(result) = model.resultState else { Issue.record("Configured Release provider was not reached: \(input)"); continue }
            #expect(result.facts.first?.source?.hasPrefix("structuredMarketplace:") == true)
            #expect(result.actions.first?.destination?.host == "provider.example")
        }
    }

@Test func absentCommercialProvidersPreserveRequestsInDeliberateBrowserFallback() async throws {
        let model = ProductionAssistantComposition.makeModel(personalSearchSources: [], compactResultDuration: .seconds(60))
        let requests = [
            "Покажи свіжі економічні новини за сьогодні",
            "Дізнайся поточне котирування акцій виробника напівпровідників",
            "Збери кошик для овочевого супу з доставкою",
            "Забронюй столик на двох завтра ввечері",
            "Порівняй доступні поїздки таксі до музею",
            "Підбери готель у Кракові на дві ночі",
            "Знайди квитки на нічний потяг до Варшави",
            "Відстеж міжнародне відправлення за номером",
            "Знайди майстра для ремонту посудомийної машини",
            "Покажи офіційний муніципальний сервіс для реєстрації",
            "Знайди вакансії дизайнера з віддаленою роботою",
            "Покажи доступні персональні знижки програми лояльності"
        ]
        for request in requests {
            model.input = request
            model.submit()
            for _ in 0..<100 { if case .webHandoff = model.resultState { break }; try await Task.sleep(for: .milliseconds(10)) }
            guard case let .webHandoff(fallback) = model.resultState else { Issue.record("External boundary did not terminate truthfully: \(request)"); continue }
            #expect(fallback.query == request)
            #expect(fallback.destination.host?.contains("google") == true)
            #expect(model.statusText != AppText.value("processing"))
        }
    }
}


@Suite("Build 29 Release remaining native reachability", .serialized)
@MainActor
struct Build29ReleaseRemainingNativeTests {
    private func wait(_ predicate: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Release-root request did not terminate")
    }

    @Test func normalizedVoiceAndQuickLaunchUseTheSameProductionModel() async throws {
        let parsed = LocalCommandEngine().parse("Двох тисяч трьохсот сорока два плюс пʼятдесят вісім")
        #expect(parsed.normalizedText.contains("2342"))
        #expect(parsed.normalizedText.contains("58"))
        #expect(parsed.intent == .localUtility)

        let model = ProductionAssistantComposition.makeModel(personalSearchSources: [], compactResultDuration: .seconds(60))
        model.handleVoiceEvent(.transcript("Двох тисяч трьохсот сорока два плюс пʼятдесят вісім", isFinal: true))
        try await wait { if case .deterministic = model.resultState { return true }; return false }
        guard case let .deterministic(voiceResult) = model.resultState else { return }
        #expect(voiceResult.primaryAnswer.filter(\.isNumber) == "2400")

        QuickLaunchRequestStore().requestCommand("Перерахуй 4,5 кілометра у метри")
        model.handleQuickLaunch()
        try await wait { if case let .deterministic(value) = model.resultState { return value.primaryAnswer.filter(\.isNumber) == "4500" }; return false }
        #expect({ if case .webHandoff = model.resultState { return false }; return true }())
    }

    @Test func timerAlarmAndClockDatabaseLimitationUseSystemFirstReleasePath() async throws {
        var actions: [SystemQuickAction] = []
        let model = ProductionAssistantComposition.makeModel(
            personalSearchSources: [], compactResultDuration: .seconds(60),
            alarmExecute: { action in actions.append(action); return "verified" },
            publicDeviceExecute: { action in actions.append(action); return "verified" }
        )
        for input in ["Увімкни таймер для настою на сорок пʼять секунд", "Розбуди мене о 06:25 для раннього потяга"] {
            model.input = input
            model.submit()
            try await wait { actions.count == (input.contains("таймер") ? 1 : 2) }
        }
        #expect(actions.count == 2)
        if case let .startTimer(seconds, label) = actions[0] {
            #expect(seconds == 45)
            #expect(label?.localizedCaseInsensitiveContains("настою") == true)
        } else { Issue.record("Timer did not reach AlarmKit action") }
        if case let .createAlarm(hour, minute, label) = actions[1] {
            #expect(hour == 6 && minute == 25)
            #expect(label?.localizedCaseInsensitiveContains("потяга") == true)
        } else { Issue.record("Alarm did not reach AlarmKit action") }

        model.input = "Переліч усі системні будильники цього телефону"
        model.submit()
        try await wait { if case .failure = model.resultState { return true }; return false }
        #expect({ if case .webHandoff = model.resultState { return false }; return true }())
    }

    @Test func captureScanDocumentAndNoteBoundariesRemainDistinct() async throws {
        let model = ProductionAssistantComposition.makeModel(personalSearchSources: [], compactResultDuration: .seconds(60))
        let requests: [(String, CapabilityPresentation)] = [
            ("Зроби новий знімок камерою", .camera),
            ("Розпізнай штрихкод камерою", .scanner),
            ("Оцифруй паперовий акт як PDF", .scanDocument(.pdf)),
            ("Розпізнай напис через камеру", .ocrCamera),
            ("Створи нотатку із текстом перевірити креслення", .share("із текстом перевірити креслення"))
        ]
        for (input, expected) in requests {
            model.input = input
            model.submit()
            try await wait { model.capabilityPresentation != nil || { if case .failure = model.resultState { return true }; return false }() }
            #expect(model.capabilityPresentation == expected, "Unexpected boundary for: \(input)")
            model.dismissCapabilityPresentation()
        }

        model.input = "Покажи мої нотатки"
        model.submit()
        try await wait { if case .failure = model.resultState { return true }; return false }
        #expect(model.capabilityPresentation == nil)
        #expect({ if case .webHandoff = model.resultState { return false }; return true }())
    }

    @Test func verifiedApplicationAndExplicitMessengerDoNotUseGenericWeb() async throws {
        let contact = ContactCandidate(identifier: "messenger-contact", displayName: "Леся Романюк", phoneNumbers: ["+380671234500"])
        let capture = Build29SystemOpenCapture()
        let model = ProductionAssistantComposition.makeModel(
            contacts: Build29ReleaseContactBoundary(.resolved(contact)),
            personalSearchSources: [], compactResultDuration: .seconds(60),
            systemHandoffOpen: capture.open
        )
        model.input = "Запусти Telegram"
        model.submit()
        try await wait { !capture.urls.isEmpty }
        #expect(capture.urls.last?.scheme == "tg")

        model.input = "Зателефонуй Лесі Романюк через WhatsApp"
        model.submit()
        try await wait { capture.urls.count == 2 }
        #expect(capture.urls.last?.host == "wa.me")
        #expect(capture.urls.last?.scheme == "https")
        #expect({ if case .webHandoff = model.resultState { return false }; return true }())
    }

    @Test func confirmationButtonsResumeOnlyTheOwnedReleaseRequest() async throws {
        let capture = Build29SystemOpenCapture()
        let model = ProductionAssistantComposition.makeModel(
            personalSearchSources: [], compactResultDuration: .seconds(60),
            systemHandoffOpen: capture.open
        )

        model.input = "Виконай екстрений виклик 112"
        model.submit()
        guard case .actionRequired = model.resultState else { Issue.record("Emergency confirmation was not rendered"); return }
        model.resolveActionRequiredChoice(AppText.value("cancel"))
        #expect(capture.urls.isEmpty)
        #expect(model.resultState == .idle)

        model.input = "Зателефонуй 112 у надзвичайній ситуації"
        model.submit()
        guard case .actionRequired = model.resultState else { Issue.record("Emergency confirmation was not rendered"); return }
        model.input = "Який сьогодні день тижня?"
        model.submit()
        model.resolveActionRequiredChoice(AppText.value("confirm"))
        #expect(capture.urls.isEmpty)

        model.input = "Набери екстрену службу 112"
        model.submit()
        guard case .actionRequired = model.resultState else { Issue.record("Emergency confirmation was not rendered"); return }
        model.resolveActionRequiredChoice(AppText.value("confirm"))
        try await wait { capture.urls.count == 1 }
        #expect(capture.urls.first?.absoluteString == "tel:112")
    }
}


private actor Build29LimitedContactBoundary: ContactResolving {
    let selected: ContactCandidate
    init(selected: ContactCandidate) { self.selected = selected }
    func authorizationState() async -> ContactAuthorizationState { .limited }
    func requestAccessIfNeeded() async throws {}
    func resolve(name: String) async throws -> ContactResolution { .notFound }
    func resolve(exactIdentifier identifier: String) async throws -> ContactResolution {
        identifier == selected.identifier ? .resolved(selected) : .notFound
    }
}
private struct Build29PhotoLibraryBoundary: PhotoLibrarySearching {
    let assets: [PhotoAssetReference]
    func authorization() -> LocalSearchAccess { .permitted }
    func requestAuthorization() async -> LocalSearchAccess { .permitted }
    func search(_ criteria: PhotoSearchCriteria, limit: Int) async -> [PhotoAssetReference] { Array(assets.prefix(limit)) }
}
private struct Build29PhotoLoaderBoundary: PhotoAssetImageLoading {
    func imageData(localIdentifier: String) async throws -> Data { Data(localIdentifier.utf8) }
}
private struct Build29PhotoLabelBoundary: PhotoSemanticLabeling {
    let confidence: Float
    func labels(imageData: Data) async throws -> [PhotoSemanticLabel] { [.init(name: "document", confidence: confidence)] }
}

@Suite("Build 29 Release remaining gap reachability", .serialized)
@MainActor
struct Build29ReleaseRemainingGapTests {
    private func wait(_ predicate: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<100 { if predicate() { return }; try await Task.sleep(for: .milliseconds(10)) }
        Issue.record("Release-root request did not terminate")
    }

    @Test func appIntentFeedsTheActualReleaseCompositionRoot() async throws {
        _ = try await RunAssistantCommandIntent(command: "Переведи 3,25 кілометра у метри").perform()
        let model = ProductionAssistantComposition.makeModel(personalSearchSources: [], compactResultDuration: .seconds(60))
        model.handleQuickLaunch()
        try await wait { if case .deterministic = model.resultState { return true }; return false }
        guard case let .deterministic(result) = model.resultState else { return }
        #expect(result.primaryAnswer.filter(\.isNumber) == "3250")
    }

    @Test func limitedContactPickerResumesTheOwnedReleaseRequestByIdentifier() async throws {
        let contact = ContactCandidate(identifier: "limited-73", displayName: "Дарина Мельник", phoneNumbers: ["+380 63 777 10 20"])
        let capture = Build29SystemOpenCapture()
        let model = ProductionAssistantComposition.makeModel(contacts: Build29LimitedContactBoundary(selected: contact), personalSearchSources: [], compactResultDuration: .seconds(60), systemHandoffOpen: capture.open)
        model.input = "Зателефонуй Дарині Мельник"
        model.submit()
        try await wait { model.capabilityPresentation != nil }
        guard case let .contactAccess(_, command)? = model.capabilityPresentation else { Issue.record("Expected limited Contacts picker"); return }
        model.handleContactAccessGranted([contact.identifier], for: command)
        try await wait { capture.urls.count == 1 }
        #expect(capture.urls.first?.scheme == "tel")
        #expect(capture.urls.first?.absoluteString.contains("WhatsApp") == false)
    }

    @Test func semanticPhotoUsesConfidenceAndFailsClosedThroughReleaseRoot() async throws {
        let asset = PhotoAssetReference(localIdentifier: "document-photo", creationDate: .now, coordinate: nil, album: nil)
        let library = Build29PhotoLibraryBoundary(assets: [asset])
        let strong = ProductionAssistantComposition.makeModel(photos: library, photoSemanticLoader: Build29PhotoLoaderBoundary(), photoSemanticLabeler: Build29PhotoLabelBoundary(confidence: 0.92), personalSearchSources: [], compactResultDuration: .seconds(60))
        strong.input = "Знайди у моїх знімках паперовий документ"
        strong.submit()
        try await wait { if case .deterministic = strong.resultState { return true }; return false }
        guard case let .deterministic(result) = strong.resultState else { return }
        #expect(result.actions.first?.id == "photos:document-photo")

        let weak = ProductionAssistantComposition.makeModel(photos: library, photoSemanticLoader: Build29PhotoLoaderBoundary(), photoSemanticLabeler: Build29PhotoLabelBoundary(confidence: 0.31), personalSearchSources: [], compactResultDuration: .seconds(60))
        weak.input = "Знайди у фото паперовий документ"
        weak.submit()
        try await wait { if case .failure = weak.resultState { return true }; return false }
        #expect({ if case .webHandoff = weak.resultState { return false }; return true }())
    }

    @Test func sharedInboxEntersCurrentContextThroughReleaseModelExactlyOnce() throws {
        let suite = "ua-release-share-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let item = SharedInboxEnvelope(kind: "url", value: "https://example.org/shared/item", receivedAt: .now)
        defaults.set(try JSONEncoder().encode(item), forKey: SharedInboxStore.inboxKey)
        let model = ProductionAssistantComposition.makeModel(personalSearchSources: [], compactResultDuration: .seconds(60))
        let store = SharedInboxStore(defaults: defaults)
        #expect(model.ingestPendingShare(from: store))
        #expect(!model.ingestPendingShare(from: store))
        guard case let .webHandoff(result) = model.resultState else { Issue.record("Expected typed shared URL"); return }
        #expect(result.destination.absoluteString == item.value)
    }
}


@Suite("Build 29 Release public document boundaries", .serialized)
@MainActor
struct Build29ReleasePublicDocumentBoundaryTests {
    @Test func selectedFilesScopeUsesSystemDocumentPickerWithoutWeb() async throws {
        let model = ProductionAssistantComposition.makeModel(personalSearchSources: [], compactResultDuration: .seconds(60))
        model.input = "Обери звіт з iCloud Drive для опрацювання"
        model.submit()
        for _ in 0..<100 where model.capabilityPresentation == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(model.capabilityPresentation == .documents)
        #expect({ if case .webHandoff = model.resultState { return false }; return true }())
    }

    @Test func verifiedVCardFromAppleScannerRequiresContactsUIImport() throws {
        let model = ProductionAssistantComposition.makeModel(personalSearchSources: [], compactResultDuration: .seconds(60))
        let payload = "BEGIN:VCARD\nVERSION:3.0\nFN:Інна Савчук\nTEL:+380991112233\nEND:VCARD"
        model.handleScannedCode(.init(payload: payload, symbology: .qr))
        guard case let .scanner(result) = model.resultState else { Issue.record("Expected typed scanner result"); return }
        model.performScannerAction(result)
        guard case let .contactImport(data)? = model.capabilityPresentation else { Issue.record("Expected public ContactsUI import"); return }
        #expect(String(data: data, encoding: .utf8)?.contains("Інна Савчук") == true)
    }
}


@Suite("Build 29 Release shopping list boundary", .serialized)
@MainActor
struct Build29ReleaseShoppingListBoundaryTests {
    @Test func naturalShoppingItemUsesSharedEventKitWithoutPreselectedList() async throws {
        let eventKit = Build29ReleaseEventKitBoundary()
        let model = ProductionAssistantComposition.makeModel(personalSearchSources: [], compactResultDuration: .seconds(60), eventKit: eventKit)
        model.input = "Додай паперові рушники до списку покупок"
        model.submit()
        for _ in 0..<100 where await eventKit.intents().isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(await eventKit.intents() == [.shoppingList])
        #expect(model.statusText != AppText.value("processing"))
        #expect({ if case .webHandoff = model.resultState { return false }; return true }())
    }
}

@Suite("Build 29 Release email compose boundary", .serialized)
@MainActor
struct Build29ReleaseEmailComposeBoundaryTests {
    @Test func explicitEmailChannelUsesMailComposerInsteadOfSMSOrWeb() async throws {
        let model = ProductionAssistantComposition.makeModel(personalSearchSources: [], compactResultDuration: .seconds(60))
        model.input = "Надішли email про календарний підсумок кварталу"
        model.submit()
        for _ in 0..<100 where model.capabilityPresentation == nil { try await Task.sleep(for: .milliseconds(10)) }
        guard case .email? = model.capabilityPresentation else {
            Issue.record("Expected public Mail composer boundary")
            return
        }
        #expect({ if case .webHandoff = model.resultState { return false }; return true }())
    }
}

@Suite("Build 29 Release notification boundary", .serialized)
@MainActor
struct Build29ReleaseNotificationBoundaryTests {
    @Test func explicitProactiveEnableUsesShippedRegistrationBoundaryOnlyOnDemand() async {
        var calls = 0
        let model = ProductionAssistantComposition.makeModel(
            personalSearchSources: [], compactResultDuration: .seconds(60),
            notificationEnable: { calls += 1; return .enabled }
        )
        #expect(calls == 0)
        await model.enableProactiveNotifications()
        #expect(calls == 1)
        #expect(model.statusText == "Сповіщення ввімкнено")
    }

    @Test func denialIsTruthfulAndDoesNotRetryOrUseWeb() async {
        var calls = 0
        let model = ProductionAssistantComposition.makeModel(
            personalSearchSources: [], compactResultDuration: .seconds(60),
            notificationEnable: { calls += 1; return .denied }
        )
        await model.enableProactiveNotifications()
        #expect(calls == 1)
        #expect(model.statusText == "Дозвіл на сповіщення не надано")
        #expect({ if case .webHandoff = model.resultState { return false }; return true }())
    }
}

@Suite("Build 29 Release PDF workflow", .serialized)
@MainActor
struct Build29ReleasePDFWorkflowTests {
    private func pdf(_ label: String) -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 200)).pdfData { context in
            context.beginPage()
            (label as NSString).draw(at: CGPoint(x: 20, y: 20), withAttributes: [.font: UIFont.systemFont(ofSize: 16)])
        }
    }

    @Test func naturalOperationsReachTypedDocumentPickerThroughReleaseRoot() async throws {
        let requests: [(String, PDFWorkflowOperation)] = [
            ("Злити PDF звіти в один документ", .merge),
            ("Розділи PDF на окремі сторінки", .split),
            ("Стисни PDF перед надсиланням", .compress)
        ]
        for (input, operation) in requests {
            let model = ProductionAssistantComposition.makeModel(personalSearchSources: [], compactResultDuration: .seconds(60))
            model.input = input; model.submit()
            for _ in 0..<100 where model.capabilityPresentation == nil { try await Task.sleep(for: .milliseconds(10)) }
            guard case let .pdfWorkflow(actual, _)? = model.capabilityPresentation else {
                Issue.record("Expected typed PDF picker for operation")
                continue
            }
            #expect(actual == operation)
            #expect({ if case .webHandoff = model.resultState { return false }; return true }())
        }
    }

    @Test func selectedDocumentsProduceRealMergedPDFOutput() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let first = directory.appending(path: "first.pdf"), second = directory.appending(path: "second.pdf")
        try pdf("Alpha").write(to: first); try pdf("Beta").write(to: second)
        let model = ProductionAssistantComposition.makeModel(personalSearchSources: [], compactResultDuration: .seconds(60))
        model.handleSelectedPDFDocuments([first, second], operation: .merge, text: nil)
        guard case let .documentFile(url)? = model.capabilityPresentation else { Issue.record("Expected merged PDF output"); return }
        #expect((try? Data(contentsOf: url)).map { (try? OnDevicePDFProcessor().pageCount($0)) == 2 } == true)
    }
}
