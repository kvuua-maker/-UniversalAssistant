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
    private let intentParser: GenericIntentParser
    private let locationResolver: ManualLocationContextResolver
    private let weatherEngine: WeatherContextEngine

    init(
        router: UniversalDeviceCommandRouter = .init(
            applications: .init(applications: LaunchDeviceApplications.verified)
        ),
        intentParser: GenericIntentParser = .init(),
        locationResolver: ManualLocationContextResolver = .init(),
        weatherEngine: WeatherContextEngine = .init(provider: AppleWeatherKitProvider())
    ) {
        self.router = router
        self.intentParser = intentParser
        self.locationResolver = locationResolver
        self.weatherEngine = weatherEngine
    }

    func execute(_ command: StructuredCommand) async throws -> WeatherSnapshot {
        guard router.route(command) == .externalCapability(.weather) else {
            throw WeatherCommandExecutionError.unsupportedRoute
        }
        LocalVoiceDiagnosticReport.shared.record("weather_route_validated", "status=success")
        let intent = try intentParser.parse(command.originalText)
        LocalVoiceDiagnosticReport.shared.record("weather_intent_parsed", "status=success")
        guard let locality = intent.location?.locality, !locality.isEmpty else {
            throw WeatherCommandExecutionError.missingLocation
        }
        LocalVoiceDiagnosticReport.shared.record("weather_location_resolution_started")
        let location: ValidatedLocation
        do {
            location = try await locationResolver.resolve(locality)
            LocalVoiceDiagnosticReport.shared.record("weather_location_resolution_succeeded", "status=success")
        } catch {
            Self.recordFailure("weather_location_resolution_failed", error: error)
            throw error
        }
        LocalVoiceDiagnosticReport.shared.record("weather_context_started")
        do {
            let snapshot = try await weatherEngine.weather(for: .init(location: location, context: .manualLocation))
            LocalVoiceDiagnosticReport.shared.record("weather_context_succeeded", "status=success")
            return snapshot
        } catch {
            Self.recordFailure("weather_context_failed", error: error)
            throw error
        }
    }

    static func recordFailure(_ marker: String, error: any Error) {
        let value = error as NSError
        LocalVoiceDiagnosticReport.shared.record(
            marker,
            "error_domain=\(value.domain) error_code=\(value.code) error_type=\(String(describing: type(of: error)))"
        )
    }
}
