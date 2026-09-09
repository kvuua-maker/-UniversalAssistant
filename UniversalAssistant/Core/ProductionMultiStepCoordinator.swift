import Foundation

typealias ProductionStepOperations = [String: CoordinationStepOperation]
typealias ProductionStepOperationFactory = @MainActor @Sendable (StructuredCommand, DeterministicExecutionPlan) -> ProductionStepOperations
typealias ProductionTypedStepExecutor = @MainActor @Sendable (StructuredCommand, ExecutionPlanStep) async throws -> ResultFact

@MainActor
final class ProductionStepOperationMap {
    private let eventKit: any EventKitCommandExecuting
    private let currentLocation: any CurrentLocationResolving
    private let locationResolver: ManualLocationContextResolver
    private let places: PlaceSearchEngine
    private let weather: any WeatherCommandExecuting
    private let navigation: NavigationHandoff
    private let typedExecutor: ProductionTypedStepExecutor?

    init(eventKit: any EventKitCommandExecuting, currentLocation: any CurrentLocationResolving,
         locationResolver: ManualLocationContextResolver, places: PlaceSearchEngine,
         weather: any WeatherCommandExecuting = ProductionWeatherCommandExecutor(),
         navigation: NavigationHandoff = .init(), typedExecutor: ProductionTypedStepExecutor? = nil) {
        self.eventKit = eventKit
        self.currentLocation = currentLocation
        self.locationResolver = locationResolver
        self.places = places
        self.weather = weather
        self.navigation = navigation
        self.typedExecutor = typedExecutor
    }

    func operations(for command: StructuredCommand, plan: DeterministicExecutionPlan) -> ProductionStepOperations {
        Dictionary(uniqueKeysWithValues: plan.steps.compactMap { step in
            operation(for: step, command: command).map { (step.id, $0) }
        })
    }

    private func operation(for step: ExecutionPlanStep, command: StructuredCommand) -> CoordinationStepOperation? {
        if [.typedCommand, .deterministicCompose].contains(step.capability) { return nil }
        if let subcommand = step.command, let typedExecutor {
            return { @MainActor in try await typedExecutor(subcommand, step) }
        }
        switch step.capability {
        case .relativeDate:
            return { [command] in
                let locale = LanguageConfiguration(uiLanguage: .uk, commandLanguage: command.language).voiceLocale
                guard case let .resolved(value) = NaturalDateTimeResolver().resolve(command.originalText, locale: locale, timeZone: .autoupdatingCurrent, relativeTo: .now) else {
                    throw CanonicalCapabilityExecutionError.missingParameter("date")
                }
                return Self.fact(step, value: value.instant.ISO8601Format(), source: "NaturalDateTimeResolver")
            }
        case .calendar:
            let eventKit = eventKit
            return { [command] in
                let result = try await eventKit.execute(Self.derived(command, intent: .calendarQuery))
                return Self.fact(step, value: "\(result.title): \(result.detail)", source: "EventKit")
            }
        case .location:
            let currentLocation = currentLocation
            return { @MainActor in
                let value = try await currentLocation.resolveCurrent(for: .navigation)
                return Self.fact(step, value: "\(value.sample.latitude),\(value.sample.longitude)", source: "CoreLocation")
            }
        case .candidateDiscovery, .places:
            let currentLocation = currentLocation
            let places = places
            return { @MainActor [command] in
                let origin = try await currentLocation.resolveCurrent(for: .nearbySearch)
                let query = command.entities["destination"] ?? command.entities["location"] ?? command.originalText
                let response = try await places.search(.init(text: query, category: nil, location: origin, limit: 3))
                guard let first = response.places.first else { throw CanonicalCapabilityExecutionError.unavailable("no_candidates") }
                return Self.fact(step, value: first.name, source: first.source)
            }
        case .route:
            let resolver = locationResolver
            let navigation = navigation
            return { [command] in
                guard let name = command.entities["destination"] ?? command.entities["location"] else {
                    throw CanonicalCapabilityExecutionError.missingParameter("destination")
                }
                let destination = try await resolver.resolve(name)
                let url = try navigation.url(provider: .appleMaps, destination: .init(latitude: destination.sample.latitude, longitude: destination.sample.longitude, name: name), mode: .driving)
                return Self.fact(step, value: url.absoluteString, source: "MapKit")
            }
        case .weather:
            let weather = weather
            return { [command] in
                let snapshot = try await weather.execute(Self.derived(command, intent: .weather))
                return Self.fact(step, value: "\(snapshot.current.temperatureCelsius) °C, \(snapshot.current.condition)", source: snapshot.source, observedAt: snapshot.fetchedAt)
            }
        case .deterministicCompose:
            return nil
        case .voice, .command:
            return { Self.fact(step, value: "validated", source: "UniversalAssistant") }
        case .typedCommand:
            return nil
        case .directAction, .transport, .hotel:
            return nil
        }
    }

    nonisolated private static func derived(_ command: StructuredCommand, intent: CommandIntent) -> StructuredCommand {
        .init(id: command.id, originalText: command.originalText, normalizedText: command.normalizedText,
              language: command.language, intent: intent, entities: command.entities,
              constraints: command.constraints, risk: command.risk, needsClarification: false)
    }

    nonisolated private static func fact(_ step: ExecutionPlanStep, value: String, source: String, observedAt: Date = .now) -> ResultFact {
        .init(id: step.id, label: step.capability.rawValue, value: value, state: .verified,
              source: source, observedAt: observedAt, priority: 100)
    }
}

@MainActor
final class ProductionMultiStepCoordinator {
    private let operationFactory: ProductionStepOperationFactory
    private let commandParser: any CommandParsing
    private var completedCommandIDs: Set<UUID> = []

    init(
        parser: any CommandParsing = LanguageUnderstandingBlock(),
        operationFactory: @escaping ProductionStepOperationFactory
    ) {
        self.commandParser = parser
        self.operationFactory = operationFactory
    }

    func execute(_ command: StructuredCommand) async throws -> DeterministicResult {
        guard !completedCommandIDs.contains(command.id) else { throw CanonicalCapabilityExecutionError.unavailable("duplicate_multi_step_command") }
        let plan = try DeterministicExecutionPlanBuilder(parser: commandParser).plan(for: command)
        let operations = operationFactory(command, plan)
        let report = try await DeterministicPlanExecutor(maximumConcurrency: 3).execute(plan, operations: operations)
        completedCommandIDs.insert(command.id)
        let ordered = plan.steps.enumerated().map { index, step -> ResultFact in
            switch report.outcomes[step.id] ?? .unavailable(.operationUnavailable) {
            case let .verified(fact): return fact
            case .unavailable: return .init(id: step.id, label: step.capability.rawValue, value: nil, state: .unavailable, source: nil, observedAt: nil, priority: 100 - index)
            }
        }
        let unavailable = ordered.filter { $0.state == .unavailable }.map(\.label)
        let completed = ordered.filter { $0.state == .verified }.count
        return try DeterministicResultComposer().compose(primaryAnswer: unavailable.isEmpty ? "Виконано всі кроки" : "Виконано \(completed) з \(ordered.count) кроків", facts: ordered, warnings: unavailable.isEmpty ? [] : ["Недоступні кроки: \(unavailable.joined(separator: ", "))"])
    }
}
