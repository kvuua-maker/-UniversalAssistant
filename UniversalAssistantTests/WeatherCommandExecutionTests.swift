import Foundation
import Testing
@testable import UniversalAssistant

private actor WeatherExecutionGeocoder: ManualLocationGeocoding {
    private(set) var labels: [String] = []

    func resolve(_ label: String) async throws -> LocationSample {
        labels.append(label)
        return .init(latitude: 50.4501, longitude: 30.5234, horizontalAccuracy: 0,
                     timestamp: .now, speed: -1, course: -1, source: .manual)
    }
}

private struct WeatherExecutionProvider: WeatherProvider {
    let providerID = "weather-test"

    func weather(for request: WeatherRequest) async throws -> WeatherSnapshot {
        .init(
            current: .init(date: .now, temperatureCelsius: 18,
                           apparentTemperatureCelsius: 17, condition: "clear",
                           symbolName: "sun.max.fill"),
            hourly: [], daily: [], source: providerID, fetchedAt: .now,
            locationSource: request.location.sample.source,
            locationLabel: request.location.manualLabel, context: request.context
        )
    }
}

private struct WeatherViewModelExecutor: WeatherCommandExecuting {
    let result: Result<WeatherSnapshot, Error>

    func execute(_ command: StructuredCommand) async throws -> WeatherSnapshot {
        try result.get()
    }
}

private actor WeatherCommandCapture {
    private(set) var commands: [StructuredCommand] = []
    func append(_ command: StructuredCommand) { commands.append(command) }
}

private struct CapturingWeatherViewModelExecutor: WeatherCommandExecuting {
    let capture: WeatherCommandCapture
    func execute(_ command: StructuredCommand) async throws -> WeatherSnapshot {
        await capture.append(command)
        return weatherExecutionSnapshot()
    }
}

private actor DeferredWeatherViewModelExecutor: WeatherCommandExecuting {
    private var continuation: CheckedContinuation<WeatherSnapshot, Error>?
    private(set) var isWaiting = false

    func execute(_ command: StructuredCommand) async throws -> WeatherSnapshot {
        isWaiting = true
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func finish(_ snapshot: WeatherSnapshot) {
        continuation?.resume(returning: snapshot)
        continuation = nil
        isWaiting = false
    }
}

private func weatherExecutionSnapshot() -> WeatherSnapshot {
    .init(
        current: .init(date: .now, temperatureCelsius: 18,
                       apparentTemperatureCelsius: 17, condition: "clear",
                       symbolName: "sun.max.fill"),
        hourly: [], daily: [], source: "weather-test", fetchedAt: .now,
        locationSource: .manual, locationLabel: "Київ", context: .manualLocation
    )
}

@MainActor
private func waitForWeatherResult(_ model: AssistantViewModel, timeout: Duration = .seconds(1)) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while model.resultState == .processing, clock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
}

@Suite("Weather command production wiring")
struct WeatherCommandExecutionTests {
    @Test func routesResolvesAndFetchesWeatherUsingExistingComponents() async throws {
        let geocoder = WeatherExecutionGeocoder()
        let executor = ProductionWeatherCommandExecutor(
            locationResolver: .init(geocoder: geocoder),
            weatherEngine: .init(provider: WeatherExecutionProvider())
        )
        let command = LocalCommandEngine().parse("Яка погода у Києві?")

        let snapshot = try await executor.execute(command)

        #expect(snapshot.locationLabel == "Києві")
        #expect(snapshot.locationSource == .manual)
        #expect(snapshot.context == .manualLocation)
        #expect(snapshot.source == "weather-test")
        #expect(await geocoder.labels == ["Києві"])
    }

    @MainActor
    @Test func arbitraryAndCurrentLocationsUseCanonicalWeatherBoundaries() async throws {
        let geocoder = WeatherExecutionGeocoder()
        let current = ValidatedLocation(sample: .init(latitude: 48.29, longitude: 25.94, horizontalAccuracy: 8, timestamp: .now, speed: -1, course: -1, source: .device), quality: .precise, isSafeForLocationActions: true, manualLabel: nil)
        let executor = ProductionWeatherCommandExecutor(locationResolver: .init(geocoder: geocoder), weatherEngine: .init(provider: WeatherExecutionProvider()), currentLocation: { _ in current })
        let arbitrary = LocalCommandEngine().parse("Покажи погоду у Чернівцях")
        #expect(arbitrary.entities["location"] == "Чернівцях")
        #expect(try await executor.execute(arbitrary).context == .manualLocation)
        #expect(await geocoder.labels == ["Чернівцях"])
        let local = LocalCommandEngine().parse("Яка зараз погода?")
        #expect(local.entities["near_current_location"] == "true")
        let snapshot = try await executor.execute(local)
        #expect(snapshot.context == .currentLocation)
        #expect(snapshot.locationSource == .device)
    }

    @MainActor
    @Test func viewModelPublishesActualWeatherSnapshotInsteadOfRecognitionCard() async throws {
        let snapshot = weatherExecutionSnapshot()
        let model = AssistantViewModel(weatherExecutor: WeatherViewModelExecutor(result: .success(snapshot)))
        model.input = "Яка погода у Києві?"

        model.submit()
        try await waitForWeatherResult(model)

        #expect(model.resultState == .weather(snapshot))
        #expect(model.statusText == AppText.value("ready"))
    }

    @MainActor
    @Test func unseenLocationReferenceComposesIntoWeatherAtHomeBoundary() async throws {
        let capture = WeatherCommandCapture()
        let model = AssistantViewModel(weatherExecutor: CapturingWeatherViewModelExecutor(capture: capture))
        model.input = "Чи холодно там, де я перебуваю?"

        model.submit()
        try await waitForWeatherResult(model)

        let command = try #require(await capture.commands.last)
        #expect(command.intent == .weather)
        #expect(command.entities["context_reference"] == "currentLocation")
        #expect(command.entities["near_current_location"] == "true")
        guard case let .weather(snapshot) = model.resultState else {
            Issue.record("Expected in-app Weather result"); return
        }
        #expect(snapshot.source == "weather-test")
        #expect(snapshot.current.temperatureCelsius == 18)
    }

    @MainActor
    @Test func weatherFailureIsTruthfulAndDoesNotShowRecognitionSuccess() async throws {
        let model = AssistantViewModel(weatherExecutor: WeatherViewModelExecutor(
            result: .failure(WeatherProviderError.unavailable)
        ))
        model.input = "Яка погода у Києві?"

        model.submit()
        try await waitForWeatherResult(model)

        guard case .failure = model.resultState else {
            Issue.record("Expected truthful weather failure")
            return
        }
    }

    @MainActor
    @Test func supersedingHomeRequestOwnsRendererAfterLateWeatherCompletion() async throws {
        let deferred = DeferredWeatherViewModelExecutor()
        let model = AssistantViewModel(weatherExecutor: deferred, compactResultDuration: .seconds(60))
        model.input = "Яка температура зараз там, де я перебуваю?"
        model.submit()
        for _ in 0..<100 where !(await deferred.isWaiting) { try await Task.sleep(for: .milliseconds(10)) }

        model.input = "Скільки буде 14 помножити на 6?"
        model.submit()
        for _ in 0..<100 {
            if case .deterministic = model.resultState { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        await deferred.finish(weatherExecutionSnapshot())
        try await Task.sleep(for: .milliseconds(50))

        guard case let .deterministic(result) = model.resultState else {
            Issue.record("Late Weather completion replaced the newer Home result"); return
        }
        #expect(result.primaryAnswer.contains("84"))
    }

    @Test func locationFailureRecordsExactFirstWeatherStageWithoutSensitiveLocation() async {
        struct FailingGeocoder: ManualLocationGeocoding {
            func resolve(_ label: String) async throws -> LocationSample { throw ManualLocationError.notFound }
        }
        let executor = ProductionWeatherCommandExecutor(locationResolver: .init(geocoder: FailingGeocoder()))
        let report = LocalVoiceDiagnosticReport.shared
        report.reset()
        do {
            _ = try await executor.execute(LocalCommandEngine().parse("Яка погода у Києві?"))
            Issue.record("Expected location resolution failure")
        } catch {
            let snapshot = report.snapshot()
            #expect(snapshot.contains("weather_location_resolution_failed"))
            #expect(!snapshot.contains("Київ"))
        }
    }
}
