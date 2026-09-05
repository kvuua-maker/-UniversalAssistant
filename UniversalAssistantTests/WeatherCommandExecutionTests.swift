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

        #expect(snapshot.locationLabel == "Київ")
        #expect(snapshot.locationSource == .manual)
        #expect(snapshot.context == .manualLocation)
        #expect(snapshot.source == "weather-test")
        #expect(await geocoder.labels == ["Київ"])
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
}
