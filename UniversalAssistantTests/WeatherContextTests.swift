import Foundation
import Testing
@testable import UniversalAssistant

private struct WeatherStub: WeatherProvider {
    let providerID = "test"
    var delay: Duration = .zero

    func weather(for request: WeatherRequest) async throws -> WeatherSnapshot {
        try await Task.sleep(for: delay)
        return .init(
            current: .init(date: .now, temperatureCelsius: 12, apparentTemperatureCelsius: 10,
                           condition: "rain", symbolName: "cloud.rain"),
            hourly: [], daily: [], source: providerID, fetchedAt: .now,
            locationSource: request.location.sample.source,
            locationLabel: request.location.manualLabel, context: request.context
        )
    }
}

private func weatherLocation(quality: LocationQuality = .good, safe: Bool = true,
                             source: LocationSource = .device, label: String? = nil) -> ValidatedLocation {
    let sample = LocationSample(latitude: 50.45, longitude: 30.52, horizontalAccuracy: 20,
                                timestamp: .now, speed: -1, course: -1, source: source)
    return .init(sample: sample, quality: quality, isSafeForLocationActions: safe, manualLabel: label)
}

@Suite("Weather context") struct WeatherContextTests {
    @Test func rejectsSuspiciousLocationBeforeProviderWork() async {
        let request = WeatherRequest(location: weatherLocation(quality: .suspicious, safe: false), context: .currentLocation)
        await #expect(throws: WeatherProviderError.unsafeLocation) {
            try await WeatherContextEngine(provider: WeatherStub()).weather(for: request)
        }
    }

    @Test func preservesManualLocationProvenanceAndContext() async throws {
        let request = WeatherRequest(location: weatherLocation(quality: .approximate, source: .manual, label: "Львів"), context: .travel)
        let result = try await WeatherContextEngine(provider: WeatherStub()).weather(for: request)
        #expect(result.locationSource == .manual)
        #expect(result.locationLabel == "Львів")
        #expect(result.context == .travel)
        #expect(result.source == "test")
    }

    @Test func enforcesBoundedProviderTimeout() async {
        let request = WeatherRequest(location: weatherLocation(), context: .destination)
        await #expect(throws: WeatherProviderError.timedOut) {
            try await WeatherContextEngine(provider: WeatherStub(delay: .seconds(1)), timeout: .milliseconds(10)).weather(for: request)
        }
    }

    @Test func recoveryNeverUsesSuspiciousReading() {
        let policy = LocationRecoveryPolicy()
        #expect(policy.actions(state: .unavailable, location: weatherLocation(quality: .suspicious, safe: false)) == [.retry, .useManualLocation])
        #expect(policy.actions(state: .denied, location: nil) == [.openSettings, .useManualLocation])
        #expect(policy.actions(state: .available, location: weatherLocation()) == [.none])
    }
}
