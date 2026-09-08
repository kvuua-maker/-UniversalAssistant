import Foundation
import Testing
@testable import UniversalAssistant

private func productionFact(_ id: String) -> ResultFact { .init(id: id, label: id, value: "done", state: .verified, source: "production-test", observedAt: .now, priority: 1) }

@MainActor
struct ProductionMultiStepTests {
    private func command(id: UUID = UUID()) -> StructuredCommand { .init(id: id, originalText: "multi", normalizedText: "multi", language: .en, intent: .multiStep) }

    @Test func productionExecutorAggregatesVerifiedAndUnavailableSteps() async throws {
        let executor = ProductionCanonicalCapabilityExecutor(multiStepOperationFactory: { _, plan in
            Dictionary(uniqueKeysWithValues: plan.steps.compactMap { step in
                if ["date", "location", "calendar"].contains(step.id) { return (step.id, { productionFact(step.id) } as CoordinationStepOperation) }
                return nil
            })
        })
        guard case let .result(result) = try await executor.execute(command()) else { Issue.record("Expected aggregate"); return }
        #expect(result.facts.contains { $0.id == "calendar" && $0.state == .verified })
        #expect(result.facts.contains { $0.id == "hotel" && $0.state == .unavailable })
        #expect(!result.warnings.isEmpty); #expect(result.aiInvocationCount == 0)
    }

    @Test func failedHardDependencyPreventsDependentOperation() async throws {
        actor Probe { var calls = 0; func call() { calls += 1 } }
        enum Failure: Error { case failed }
        let probe = Probe()
        let plan = DeterministicExecutionPlan(commandID: UUID(), intent: .multiStep, constraints: [], steps: [.init(id: "first", capability: .location, dependencies: []), .init(id: "second", capability: .route, dependencies: ["first"])], completionStepID: "second", aiInvocationCount: 0)
        let report = try await DeterministicPlanExecutor().execute(plan, operations: ["first": { throw Failure.failed }, "second": { await probe.call(); return productionFact("second") }])
        #expect(report.outcomes["first"] == .unavailable(.providerFailure))
        #expect(report.outcomes["second"] == .unavailable(.operationUnavailable))
        #expect(await probe.calls == 0)
    }

    @Test func duplicateCommandIsRejectedAfterCompletedPartialExecution() async throws {
        let id = UUID(); let coordinator = ProductionMultiStepCoordinator(operationFactory: { _, _ in [:] })
        let first = try await coordinator.execute(command(id: id)); #expect(first.facts.allSatisfy { $0.state == .unavailable })
        await #expect(throws: CanonicalCapabilityExecutionError.unavailable("duplicate_multi_step_command")) { try await coordinator.execute(command(id: id)) }
    }

    @Test func executorPreservesExistingConcurrencyTimeoutAndCancellationSemantics() async throws {
        let plan = DeterministicExecutionPlan(commandID: UUID(), intent: .multiStep, constraints: [], steps: [.init(id: "fast", capability: .weather, dependencies: []), .init(id: "slow", capability: .hotel, dependencies: [])], completionStepID: "fast", aiInvocationCount: 0)
        let report = try await DeterministicPlanExecutor(maximumConcurrency: 2, operationTimeout: .milliseconds(30)).execute(plan, operations: ["fast": { productionFact("fast") }, "slow": { try await Task.sleep(for: .seconds(1)); return productionFact("slow") }])
        if case let .verified(fact) = report.outcomes["fast"] { #expect(fact.id == "fast") } else { Issue.record("Expected verified fast step") }
        #expect(report.outcomes["slow"] == .unavailable(.timeout))
        #expect(report.maximumObservedConcurrency == 2)
    }
}

private actor MultiStepEventKitStub: EventKitCommandExecuting {
    private(set) var intents: [CommandIntent] = []
    func execute(_ command: StructuredCommand) async throws -> EventKitExecutionResult {
        intents.append(command.intent)
        return .init(kind: .calendar, operation: .queried, title: "Calendar", detail: "one item", itemCount: 1)
    }
}
@MainActor private final class MultiStepLocationStub: CurrentLocationResolving {
    private(set) var purposes: [LocationPurpose] = []
    let value = ValidatedLocation(sample: .init(latitude: 50.45, longitude: 30.52, horizontalAccuracy: 4, timestamp: .now, speed: 0, course: 0, source: .device), quality: .precise, isSafeForLocationActions: true, manualLabel: nil)
    func resolveCurrent(for purpose: LocationPurpose) async throws -> ValidatedLocation { purposes.append(purpose); return value }
}
private actor MultiStepGeocoderStub: ManualLocationGeocoding {
    func resolve(_ label: String) async throws -> LocationSample {
        .init(latitude: 50.45, longitude: 30.52, horizontalAccuracy: 0, timestamp: .now, speed: -1, course: -1, source: .manual)
    }
}
private struct MultiStepPlaceStub: PlaceProvider {
    let providerID = "multi-step-place"
    func search(_ query: PlaceQuery) async throws -> [Place] {
        [.init(id: "candidate-1", providerID: providerID, name: "Candidate", category: .other, latitude: 50.46, longitude: 30.53, source: providerID, timestamp: .now, verification: .providerVerified)]
    }
}
private struct MultiStepWeatherStub: WeatherCommandExecuting {
    func execute(_ command: StructuredCommand) async throws -> WeatherSnapshot {
        .init(current: .init(date: .now, temperatureCelsius: 20, apparentTemperatureCelsius: 20, condition: "clear", symbolName: "sun.max"),
              hourly: [], daily: [], source: "WeatherKit", fetchedAt: .now, locationSource: .manual, locationLabel: "Kyiv", context: .travel)
    }
}

extension ProductionMultiStepTests {
    @Test func concreteProductionStepInvokesBoundRealExecutor() async throws {
        actor Probe {
            var intents: [CommandIntent] = []
            func record(_ intent: CommandIntent) { intents.append(intent) }
        }
        let probe = Probe()
        let subcommand = StructuredCommand(originalText: "record", normalizedText: "record", language: .en, intent: .audioRecord)
        let step = ExecutionPlanStep(id: "step-01-audioRecord", capability: .directAction, dependencies: [], command: subcommand)
        let plan = DeterministicExecutionPlan(commandID: UUID(), intent: .multiStep, constraints: [], steps: [step], completionStepID: step.id, aiInvocationCount: 0)
        let map = ProductionStepOperationMap(eventKit: MultiStepEventKitStub(), currentLocation: MultiStepLocationStub(),
            locationResolver: .init(geocoder: MultiStepGeocoderStub()), places: .init(providers: [MultiStepPlaceStub()]),
            typedExecutor: { command, step in await probe.record(command.intent); return productionFact(step.id) })
        let operation = try #require(map.operations(for: command(), plan: plan)[step.id])
        #expect(try await operation().id == step.id)
        #expect(await probe.intents == [.audioRecord])
    }

    @Test func abstractPlannerIdentifiersAreNeverExecutable() {
        let abstract = [
            ExecutionPlanStep(id: "typed", capability: .typedCommand, dependencies: [], command: StructuredCommand(originalText: "open", normalizedText: "open", language: .en, intent: .open)),
            ExecutionPlanStep(id: "compose", capability: .deterministicCompose, dependencies: [])
        ]
        let plan = DeterministicExecutionPlan(commandID: UUID(), intent: .multiStep, constraints: [], steps: abstract, completionStepID: "compose", aiInvocationCount: 0)
        let map = ProductionStepOperationMap(eventKit: MultiStepEventKitStub(), currentLocation: MultiStepLocationStub(), locationResolver: .init(geocoder: MultiStepGeocoderStub()), places: .init(providers: [MultiStepPlaceStub()]), typedExecutor: { _, step in productionFact(step.id) })
        #expect(map.operations(for: command(), plan: plan).isEmpty)
    }

    @Test func typedProductionStepWithoutEligibleExecutorRemainsTruthfullyUnavailable() {
        let subcommand = StructuredCommand(originalText: "blocked", normalizedText: "blocked", language: .en, intent: .hotelSearch)
        let step = ExecutionPlanStep(id: "blocked", capability: .directAction, dependencies: [], command: subcommand)
        let plan = DeterministicExecutionPlan(commandID: UUID(), intent: .multiStep, constraints: [], steps: [step], completionStepID: step.id, aiInvocationCount: 0)
        #expect(liveMap().operations(for: command(), plan: plan)[step.id] == nil)
    }

    private func liveMapPlan() -> DeterministicExecutionPlan {
        .init(commandID: UUID(), intent: .multiStep, constraints: [], steps: [
            .init(id: "date", capability: .relativeDate, dependencies: []),
            .init(id: "calendar", capability: .calendar, dependencies: []),
            .init(id: "location", capability: .location, dependencies: []),
            .init(id: "candidates", capability: .candidateDiscovery, dependencies: []),
            .init(id: "route", capability: .route, dependencies: []),
            .init(id: "weather", capability: .weather, dependencies: []),
            .init(id: "transport", capability: .transport, dependencies: []),
            .init(id: "hotel", capability: .hotel, dependencies: [])
        ], completionStepID: "weather", aiInvocationCount: 0)
    }
    private func liveMapCommand() -> StructuredCommand {
        .init(originalText: "Tomorrow in Kyiv", normalizedText: "tomorrow in kyiv", language: .en, intent: .multiStep, entities: ["destination":"Kyiv"])
    }
    private func liveMap() -> ProductionStepOperationMap {
        .init(eventKit: MultiStepEventKitStub(), currentLocation: MultiStepLocationStub(),
              locationResolver: .init(geocoder: MultiStepGeocoderStub()),
              places: .init(providers: [MultiStepPlaceStub()]), weather: MultiStepWeatherStub())
    }

    @Test func liveFactoryMapsEveryEligiblePlanCapability() {
        let operations = liveMap().operations(for: liveMapCommand(), plan: liveMapPlan())
        #expect(Set(operations.keys) == ["date","calendar","location","candidates","route","weather"])
    }
    @Test func blockedExternalProvidersHaveNoFakeOperations() {
        let operations = liveMap().operations(for: liveMapCommand(), plan: liveMapPlan())
        #expect(operations["transport"] == nil); #expect(operations["hotel"] == nil)
    }
    @Test func liveDateOperationUsesDeterministicResolver() async throws {
        let operations = liveMap().operations(for: liveMapCommand(), plan: liveMapPlan())
        #expect(try await operations["date"]?().source == "NaturalDateTimeResolver")
    }
    @Test func liveCalendarOperationUsesEventKit() async throws {
        let operations = liveMap().operations(for: liveMapCommand(), plan: liveMapPlan())
        #expect(try await operations["calendar"]?().source == "EventKit")
    }
    @Test func liveLocationOperationUsesCoreLocation() async throws {
        let operations = liveMap().operations(for: liveMapCommand(), plan: liveMapPlan())
        #expect(try await operations["location"]?().source == "CoreLocation")
    }
    @Test func liveCandidateOperationUsesPlaceEngine() async throws {
        let operations = liveMap().operations(for: liveMapCommand(), plan: liveMapPlan())
        #expect(try await operations["candidates"]?().value == "Candidate")
    }
    @Test func liveRouteOperationProducesMapsURLFact() async throws {
        let operations = liveMap().operations(for: liveMapCommand(), plan: liveMapPlan())
        #expect(try await operations["route"]?().value?.hasPrefix("https://") == true)
    }
    @Test func liveWeatherOperationUsesWeatherExecutor() async throws {
        let operations = liveMap().operations(for: liveMapCommand(), plan: liveMapPlan())
        #expect(try await operations["weather"]?().source == "WeatherKit")
    }

    @Test func naturalPlaceThenNavigationExecutesConcreteProductionSteps() async throws {
        let location = MultiStepLocationStub()
        let context = CurrentContextStore()
        let executor = ProductionCanonicalCapabilityExecutor(
            locationResolver: .init(geocoder: MultiStepGeocoderStub()),
            placeSearch: .init(providers: [MultiStepPlaceStub()]),
            currentLocation: location, currentContext: context, personalSearchSources: []
        )
        let command = LocalCommandEngine().parse("Знайди магазин Nike у Києві і покажи, як до нього доїхати")
        #expect(command.intent == .multiStep)
        let planned = try DeterministicExecutionPlanBuilder().plan(for: command)
        #expect(planned.steps.compactMap(\.command?.intent) == [.placeSearch, .navigation])
        guard case let .handoff(result) = try await executor.execute(command) else { Issue.record("Expected final navigation handoff"); return }
        #expect(result.kind == .navigation)
        #expect(result.destination.host == "maps.apple.com")
        #expect(result.destination.absoluteString.contains("50.46"))
    }

    @Test func unseenPlaceCompositionBindsResolvedCoordinatesWithoutSecondGeocode() async throws {
        let executor = ProductionCanonicalCapabilityExecutor(
            locationResolver: .init(geocoder: MultiStepGeocoderStub()),
            placeSearch: .init(providers: [MultiStepPlaceStub()]),
            currentLocation: MultiStepLocationStub(), personalSearchSources: []
        )
        let command = LocalCommandEngine().parse("Знайди найближчий ресторан у Львові, потім проклади до нього маршрут")
        #expect(command.intent == .multiStep)
        guard case let .handoff(result) = try await executor.execute(command) else { Issue.record("Expected typed navigation handoff"); return }
        #expect(result.kind == .navigation)
        #expect(result.destination.absoluteString.contains("50.46"))
    }
}
