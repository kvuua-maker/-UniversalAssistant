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
