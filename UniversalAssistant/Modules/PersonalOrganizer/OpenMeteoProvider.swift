import Foundation

/// WeatherKit requires a paid Apple Developer entitlement and fails in a sandbox
/// without it (`xpcConnectionFailed`). Open-Meteo needs no key, so it keeps the
/// weather feature usable in every build.
struct OpenMeteoProvider: WeatherProvider {
    let providerID = "open-meteo"

    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let apparent_temperature: Double
            let weather_code: Int
        }
        struct Hourly: Decodable {
            let time: [String]
            let temperature_2m: [Double]
            let precipitation_probability: [Int]
            let weather_code: [Int]
        }
        struct Daily: Decodable {
            let time: [String]
            let temperature_2m_min: [Double]
            let temperature_2m_max: [Double]
            let precipitation_probability_max: [Int]
            let weather_code: [Int]
        }
        let current: Current
        let hourly: Hourly
        let daily: Daily
    }

    func weather(for request: WeatherRequest) async throws -> WeatherSnapshot {
        let request = try request.validated()
        let sample = request.location.sample
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(sample.latitude)&longitude=\(sample.longitude)&current=temperature_2m,apparent_temperature,weather_code&hourly=temperature_2m,precipitation_probability,weather_code&daily=temperature_2m_min,temperature_2m_max,precipitation_probability_max,weather_code&timezone=auto&forecast_days=7"
        guard let url = URL(string: urlString) else { throw WeatherProviderError.unavailable }

        var urlRequest = URLRequest(url: url)
        urlRequest.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw WeatherProviderError.unavailable
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        func date(_ value: String) -> Date {
            formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value + ":00") ?? Date()
        }

        let current = CurrentWeatherValue(
            date: Date(),
            temperatureCelsius: decoded.current.temperature_2m,
            apparentTemperatureCelsius: decoded.current.apparent_temperature,
            condition: Self.description(for: decoded.current.weather_code),
            symbolName: Self.symbol(for: decoded.current.weather_code)
        )
        let count = min(decoded.hourly.time.count,
                        decoded.hourly.temperature_2m.count,
                        decoded.hourly.weather_code.count,
                        decoded.hourly.precipitation_probability.count)
        let hourly = (0..<min(count, request.hourlyLimit)).map { index in
            HourlyWeatherValue(
                date: date(decoded.hourly.time[index]),
                temperatureCelsius: decoded.hourly.temperature_2m[index],
                precipitationChance: Double(decoded.hourly.precipitation_probability[index]) / 100,
                condition: Self.description(for: decoded.hourly.weather_code[index]),
                symbolName: Self.symbol(for: decoded.hourly.weather_code[index])
            )
        }
        let dailyCount = min(decoded.daily.time.count,
                             decoded.daily.temperature_2m_min.count,
                             decoded.daily.temperature_2m_max.count,
                             decoded.daily.weather_code.count)
        let daily = (0..<min(dailyCount, request.dailyLimit)).map { index in
            DailyWeatherValue(
                date: ISO8601DateFormatter().date(from: decoded.daily.time[index] + "T12:00:00Z") ?? Date(),
                lowTemperatureCelsius: decoded.daily.temperature_2m_min[index],
                highTemperatureCelsius: decoded.daily.temperature_2m_max[index],
                precipitationChance: Double(decoded.daily.precipitation_probability_max.indices.contains(index) ? decoded.daily.precipitation_probability_max[index] : 0) / 100,
                condition: Self.description(for: decoded.daily.weather_code[index]),
                symbolName: Self.symbol(for: decoded.daily.weather_code[index])
            )
        }
        return WeatherSnapshot(
            current: current,
            hourly: hourly,
            daily: daily,
            source: providerID,
            fetchedAt: Date(),
            locationSource: .manual,
            locationLabel: request.location.manualLabel,
            context: request.context
        )
    }

    static func description(for code: Int) -> String {
        switch code {
        case 0: "Ясно"
        case 1, 2: "Мінлива хмарність"
        case 3: "Хмарно"
        case 45, 48: "Туман"
        case 51, 53, 55, 56, 57: "Мряка"
        case 61, 63, 65, 66, 67: "Дощ"
        case 71, 73, 75, 77: "Сніг"
        case 80, 81, 82: "Злива"
        case 85, 86: "Снігопад"
        case 95, 96, 99: "Гроза"
        default: "Невідомо"
        }
    }

    static func symbol(for code: Int) -> String {
        switch code {
        case 0: "sun.max.fill"
        case 1, 2: "cloud.sun.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55, 56, 57: "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67: "cloud.rain.fill"
        case 71, 73, 75, 77: "snowflake"
        case 80, 81, 82: "cloud.heavyrain.fill"
        case 85, 86: "cloud.snow.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }
}

/// Tries WeatherKit first and falls back to Open-Meteo when Apple's service is
/// unavailable (missing entitlement, sandbox restriction, network error).
struct ResilientWeatherProvider: WeatherProvider {
    let providerID = "weatherkit+open-meteo"
    private let primary: any WeatherProvider = AppleWeatherKitProvider()
    private let fallback: any WeatherProvider = OpenMeteoProvider()

    func weather(for request: WeatherRequest) async throws -> WeatherSnapshot {
        do {
            return try await primary.weather(for: request)
        } catch {
            await MainActor.run {
                RuntimeDiagnostics.shared.log("weather", "WeatherKit unavailable, using Open-Meteo: \\(error)")
            }
            return try await fallback.weather(for: request)
        }
    }
}
