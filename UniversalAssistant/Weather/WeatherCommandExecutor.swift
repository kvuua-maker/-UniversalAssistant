import Foundation

enum WeatherCommandExecutionError: Error, Equatable, Sendable {
    case unsupportedRoute
    case missingLocation
}

protocol WeatherCommandExecuting: Sendable {
    func execute(_ command: StructuredCommand) async throws -> WeatherSnapshot
}

struct ProductionWeatherCommandExecutor: WeatherCommandExecuting, Sendable {
    private let router: UniversalDeviceCommandRouter
    private let locationResolver: ManualLocationContextResolver
    private let weatherEngine: WeatherContextEngine
    private let currentLocation: @MainActor @Sendable (LocationPurpose) async throws -> ValidatedLocation
    private let recordDiagnostic: @Sendable (String, String) -> Void

    init(
        router: UniversalDeviceCommandRouter = .init(
            applications: .init(applications: LaunchDeviceApplications.verified)
        ),
        locationResolver: ManualLocationContextResolver = .init(),
        weatherEngine: WeatherContextEngine = .init(provider: AppleWeatherKitProvider()),
        currentLocation: @escaping @MainActor @Sendable (LocationPurpose) async throws -> ValidatedLocation = { purpose in try await AppleCurrentLocationResolver().resolveCurrent(for: purpose) },
        recordDiagnostic: @escaping @Sendable (String, String) -> Void = { marker, details in
            LocalVoiceDiagnosticReport.shared.record(marker, details)
        }
    ) {
        self.router = router
        self.locationResolver = locationResolver
        self.weatherEngine = weatherEngine
        self.currentLocation = currentLocation
        self.recordDiagnostic = recordDiagnostic
    }

    func execute(_ command: StructuredCommand) async throws -> WeatherSnapshot {
        recordDiagnostic("WEATHER_PRE", "capability=weather")
        defer { recordDiagnostic("WEATHER_POST", "capability=weather status=returned") }
        guard router.route(command) == .externalCapability(.weather) else {
            throw WeatherCommandExecutionError.unsupportedRoute
        }
        recordDiagnostic("weather_route_validated", "status=success")
        recordDiagnostic("weather_intent_parsed", "status=success")
        recordDiagnostic("weather_location_resolution_started", "")
        let location: ValidatedLocation
        let context: WeatherContextKind
        do {
            if let locality = command.entities["location"], !locality.isEmpty {
                location = try await locationResolver.resolve(locality); context = .manualLocation
            } else {
                location = try await currentLocation(.general); context = .currentLocation
            }
            recordDiagnostic("weather_location_resolution_succeeded", "status=success")
        } catch {
            recordExecutionFailure("weather_location_resolution_failed", error: error)
            throw error
        }
        recordDiagnostic("weather_context_started", "")
        do {
            let locale = LanguageConfiguration(uiLanguage: .uk, commandLanguage: command.language).voiceLocale
            let targetDate: Date? = {
                if case let .resolved(value) = NaturalDateTimeResolver().resolve(
                    command, locale: locale, timeZone: .autoupdatingCurrent, relativeTo: .now
                ) { return value.instant }
                return nil
            }()
            let snapshot = try await weatherEngine.weather(for: .init(
                location: location,
                context: context,
                targetDate: targetDate
            ))
            recordDiagnostic("weather_context_succeeded", "status=success")
            return snapshot
        } catch {
            recordExecutionFailure("weather_context_failed", error: error)
            throw error
        }
    }

    private func recordExecutionFailure(_ marker: String, error: any Error) {
        let value = error as NSError
        recordDiagnostic(
            marker,
            "error_domain=\(value.domain) error_code=\(value.code) error_type=\(String(describing: type(of: error)))"
        )
    }

    static func recordFailure(_ marker: String, error: any Error) {
        let value = error as NSError
        LocalVoiceDiagnosticReport.shared.record(
            marker,
            "error_domain=\(value.domain) error_code=\(value.code) error_type=\(String(describing: type(of: error)))"
        )
    }
}
