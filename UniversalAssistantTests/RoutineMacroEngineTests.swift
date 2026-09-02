import XCTest
@testable import UniversalAssistant

final class RoutineMacroEngineTests: XCTestCase {
    private static func fact(_ id: String) -> ResultFact {
        .init(id: id, label: id, value: "ok", state: .verified, source: "test", observedAt: Date(), priority: 1)
    }

    func testNaturalRoutineCompilesIntoTypedDependencyGraph() throws {
        let engine = RoutineMacroEngine(executor: try .init())
        let routine = try engine.makeRoutine(from: "Коли я кажу їду на роботу, відкривай маршрут, покажи час дороги і першу зустріч")
        XCTAssertEqual(routine.actions.map(\.id), ["route", "travel-time", "next-event"])
        XCTAssertEqual(routine.actions.first { $0.id == "travel-time" }?.dependencies, ["route"])
        XCTAssertTrue(try DeterministicExecutionPlan(commandID: routine.id, intent: .multiStep, constraints: [], steps: routine.actions.map { .init(id: $0.id, capability: $0.capability, dependencies: $0.dependencies) }, completionStepID: "next-event", aiInvocationCount: 0).parallelGroups().first?.contains(where: { $0.id == "next-event" }) == true)
    }

    func testStorePersistsEditEnableDisableAndDelete() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let local = LocalStore(baseDirectory: directory)
        let store = RoutineMacroStore(store: local)
        let routine = try RoutineMacroEngine(executor: .init()).makeRoutine(from: "Коли я кажу додому, відкривай маршрут і покажи магазин")
        try await store.save(routine)
        try await store.update(routine.id) { $0.isEnabled = false; $0.name = "Додому" }
        let reloaded = try await RoutineMacroStore(store: local).all().first
        XCTAssertEqual(reloaded?.name, "Додому"); XCTAssertEqual(reloaded?.isEnabled, false); XCTAssertEqual(reloaded?.revision, 2)
        try await store.delete(routine.id)
        let remaining = try await store.all()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testIndependentStepsRunConcurrentlyAndDependencyWaits() async throws {
        let routine = RoutineMacro(id: UUID(), name: "work", trigger: .exactPhrase("work"), conditions: [.always], actions: [
            .init(id: "route", capability: .transport, dependencies: [], parameters: [:], requiredPermission: nil, risk: .informational),
            .init(id: "calendar", capability: .calendar, dependencies: [], parameters: [:], requiredPermission: nil, risk: .informational),
            .init(id: "compose", capability: .deterministicCompose, dependencies: ["route", "calendar"], parameters: [:], requiredPermission: nil, risk: .informational)
        ], isEnabled: true, revision: 1, createdAt: Date(), updatedAt: Date())
        let engine = RoutineMacroEngine(executor: try .init(maximumConcurrency: 2), ledger: .init(store: LocalStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))))
        let result = try await engine.execute(routine, phrase: "work", eventID: "1", operations: [
            "route": { try await Task.sleep(for: .milliseconds(30)); return Self.fact("route") },
            "calendar": { try await Task.sleep(for: .milliseconds(30)); return Self.fact("calendar") },
            "compose": { Self.fact("compose") }
        ])
        guard case let .executed(report) = result else { return XCTFail() }
        XCTAssertEqual(report.maximumObservedConcurrency, 2); XCTAssertEqual(report.aiInvocationCount, 0)
    }

    func testPermissionConfirmationPartialFailureAndIdempotency() async throws {
        let routine = RoutineMacro(id: UUID(), name: "safe", trigger: .exactPhrase("go"), conditions: [.always], actions: [
            .init(id: "local", capability: .directAction, dependencies: [], parameters: [:], requiredPermission: nil, risk: .reversible),
            .init(id: "location", capability: .transport, dependencies: [], parameters: [:], requiredPermission: "location", risk: .informational),
            .init(id: "purchase", capability: .directAction, dependencies: [], parameters: [:], requiredPermission: nil, risk: .consequential)
        ], isEnabled: true, revision: 1, createdAt: Date(), updatedAt: Date())
        let engine = RoutineMacroEngine(executor: try .init(), ledger: .init(store: LocalStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))))
        let operations = Dictionary(uniqueKeysWithValues: routine.actions.map { action in (action.id, { Self.fact(action.id) } as CoordinationStepOperation) })
        let first = try await engine.execute(routine, phrase: "go", eventID: "event", operations: operations)
        guard case let .executed(report) = first else { return XCTFail() }
        guard case let .verified(localFact) = report.outcomes["local"] else { return XCTFail() }
        XCTAssertEqual(localFact.id, "local")
        XCTAssertEqual(report.outcomes["location"], .unavailable(.permissionDenied))
        XCTAssertEqual(report.outcomes["purchase"], .unavailable(.confirmationRequired))
        let duplicate = try await engine.execute(routine, phrase: "go", eventID: "event", operations: operations)
        XCTAssertEqual(duplicate, .duplicate)
    }

    func testCycleRejectedAndCancellationPropagates() async throws {
        var routine = RoutineMacro(id: UUID(), name: "cycle", trigger: .exactPhrase("x"), conditions: [.always], actions: [
            .init(id: "a", capability: .directAction, dependencies: ["b"], parameters: [:], requiredPermission: nil, risk: .informational),
            .init(id: "b", capability: .directAction, dependencies: ["a"], parameters: [:], requiredPermission: nil, risk: .informational)
        ], isEnabled: true, revision: 1, createdAt: Date(), updatedAt: Date())
        XCTAssertThrowsError(try RoutineMacroStore.validate(routine))
        routine.actions = [.init(id: "a", capability: .directAction, dependencies: [], parameters: [:], requiredPermission: nil, risk: .informational)]
        let executableRoutine = routine
        let engine = RoutineMacroEngine(executor: try .init(), ledger: .init(store: LocalStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))))
        let result = try await engine.execute(executableRoutine, phrase: "x", eventID: "cancel", operations: ["a": { throw CancellationError() }])
        guard case let .executed(report) = result else { return XCTFail() }
        XCTAssertEqual(report.outcomes["a"], .unavailable(.cancelled))
    }
}
