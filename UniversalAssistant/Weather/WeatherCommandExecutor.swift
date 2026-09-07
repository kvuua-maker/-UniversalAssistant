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

    init(
        router: UniversalDeviceCommandRouter = .init(
            applications: .init(applications: LaunchDeviceApplications.verified)
        ),
        locationResolver: ManualLocationContextResolver = .init(),
        weatherEngine: WeatherContextEngine = .init(provider: AppleWeatherKitProvider()),
        currentLocation: @escaping @MainActor @Sendable (LocationPurpose) async throws -> ValidatedLocation = { purpose in try await AppleCurrentLocationResolver().resolveCurrent(for: purpose) }
    ) {
        self.router = router
        self.locationResolver = locationResolver
        self.weatherEngine = weatherEngine
        self.currentLocation = currentLocation
    }

    func execute(_ command: StructuredCommand) async throws -> WeatherSnapshot {
        guard router.route(command) == .externalCapability(.weather) else {
            throw WeatherCommandExecutionError.unsupportedRoute
        }
        LocalVoiceDiagnosticReport.shared.record("weather_route_validated", "status=success")
        LocalVoiceDiagnosticReport.shared.record("weather_intent_parsed", "status=success")
        LocalVoiceDiagnosticReport.shared.record("weather_location_resolution_started")
        let location: ValidatedLocation
        let context: WeatherContextKind
        do {
            if let locality = command.entities["location"], !locality.isEmpty {
                location = try await locationResolver.resolve(locality); context = .manualLocation
            } else {
                location = try await currentLocation(.general); context = .currentLocation
            }
            LocalVoiceDiagnosticReport.shared.record("weather_location_resolution_succeeded", "status=success")
        } catch {
            Self.recordFailure("weather_location_resolution_failed", error: error)
            throw error
        }
        LocalVoiceDiagnosticReport.shared.record("weather_context_started")
        do {
            let snapshot = try await weatherEngine.weather(for: .init(location: location, context: context))
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
