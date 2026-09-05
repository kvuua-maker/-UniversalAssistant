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
        let intent = try intentParser.parse(command.originalText)
        guard let locality = intent.location?.locality, !locality.isEmpty else {
            throw WeatherCommandExecutionError.missingLocation
        }
        let location = try await locationResolver.resolve(locality)
        return try await weatherEngine.weather(
            for: .init(location: location, context: .manualLocation)
        )
    }
}
