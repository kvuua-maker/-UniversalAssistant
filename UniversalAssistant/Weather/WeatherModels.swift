import Foundation

enum WeatherContextKind: String, Codable, Sendable {
    case currentLocation, manualLocation, destination, event, travel
}
struct WeatherRequest: Equatable, Sendable {
    let location: ValidatedLocation
    let context: WeatherContextKind
    var targetDate: Date? = nil
    var hourlyLimit = 24
    var dailyLimit = 10

    func validated() throws -> Self {
        guard location.isSafeForLocationActions,
              location.quality != .suspicious,
              location.quality != .unavailable else { throw WeatherProviderError.unsafeLocation }
        guard (1...48).contains(hourlyLimit), (1...10).contains(dailyLimit) else {
            throw WeatherProviderError.invalidBounds
        }
        return self
    }
}

struct CurrentWeatherValue: Equatable, Codable, Sendable {
    let date: Date
    let temperatureCelsius: Double
    let apparentTemperatureCelsius: Double
    let condition: String
    let symbolName: String
}

struct HourlyWeatherValue: Equatable, Codable, Sendable {
    let date: Date
    let temperatureCelsius: Double
    let precipitationChance: Double
    let condition: String
    let symbolName: String
}

struct DailyWeatherValue: Equatable, Codable, Sendable {
    let date: Date
    let lowTemperatureCelsius: Double
    let highTemperatureCelsius: Double
    let precipitationChance: Double
    let condition: String
    let symbolName: String
}

struct WeatherSnapshot: Equatable, Codable, Sendable {
    let current: CurrentWeatherValue
    let hourly: [HourlyWeatherValue]
    let daily: [DailyWeatherValue]
    let source: String
    let fetchedAt: Date
    let locationSource: LocationSource
    let locationLabel: String?
    let context: WeatherContextKind
    var requestedDate: Date? = nil
}

enum WeatherProviderError: Error, Equatable, Sendable {
    case unsafeLocation, invalidBounds, timedOut, unavailable
}

protocol WeatherProvider: Sendable {
    var providerID: String { get }
    func weather(for request: WeatherRequest) async throws -> WeatherSnapshot
}
