import Foundation
import Testing
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
