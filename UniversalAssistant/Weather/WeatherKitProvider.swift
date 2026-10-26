import CoreLocation
import Foundation
import WeatherKit

struct AppleWeatherKitProvider: WeatherProvider {
    let providerID = "apple-weatherkit"
    private let service = WeatherService.shared

    func weather(for request: WeatherRequest) async throws -> WeatherSnapshot {
        let request = try request.validated()
        let sample = request.location.sample
        LocalVoiceDiagnosticReport.shared.record("weatherkit_request_started")
        let weather: Weather
        do {
            weather = try await service.weather(for: CLLocation(latitude: sample.latitude, longitude: sample.longitude))
            LocalVoiceDiagnosticReport.shared.record("weatherkit_response_received", "status=success")
        } catch {
            await MainActor.run {
                RuntimeDiagnostics.shared.log("weather", "WeatherKit failed: \(error)")
            }
            ProductionWeatherCommandExecutor.recordFailure("weatherkit_request_failed", error: error)
            throw error
        }
        let current = weather.currentWeather
        let snapshot = WeatherSnapshot(
            current: .init(
                date: current.date,
                temperatureCelsius: current.temperature.converted(to: .celsius).value,
                apparentTemperatureCelsius: current.apparentTemperature.converted(to: .celsius).value,
                condition: String(describing: current.condition),
                symbolName: current.symbolName
            ),
            hourly: weather.hourlyForecast.prefix(request.hourlyLimit).map {
                .init(date: $0.date, temperatureCelsius: $0.temperature.converted(to: .celsius).value,
                      precipitationChance: $0.precipitationChance, condition: String(describing: $0.condition),
                      symbolName: $0.symbolName)
            },
            daily: weather.dailyForecast.prefix(request.dailyLimit).map {
                .init(date: $0.date, lowTemperatureCelsius: $0.lowTemperature.converted(to: .celsius).value,
                      highTemperatureCelsius: $0.highTemperature.converted(to: .celsius).value,
                      precipitationChance: $0.precipitationChance, condition: String(describing: $0.condition),
                      symbolName: $0.symbolName)
            },
            source: providerID,
            fetchedAt: .now,
            locationSource: sample.source,
            locationLabel: request.location.manualLabel,
            context: request.context,
            requestedDate: request.targetDate
        )
        LocalVoiceDiagnosticReport.shared.record("weather_result_mapped", "status=success")
        return snapshot
    }
}
