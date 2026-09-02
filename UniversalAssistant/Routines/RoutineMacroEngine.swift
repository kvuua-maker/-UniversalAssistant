import Foundation

enum RoutineTrigger: Equatable, Codable, Sendable {
    case exactPhrase(String)
}

enum RoutineCondition: Equatable, Codable, Sendable {
    case always
    case contextFlag(key: String, expectedValue: String)
}

struct RoutineAction: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let capability: ExecutionCapability
    let dependencies: Set<String>
    let parameters: [String: String]
    let requiredPermission: String?
    let risk: ActionRisk
}

struct RoutineMacro: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var name: String
    var trigger: RoutineTrigger
    var conditions: [RoutineCondition]
    var actions: [RoutineAction]
    var isEnabled: Bool
    var revision: Int
    let createdAt: Date
    var updatedAt: Date
}

enum RoutineMacroError: Error, Equatable {
    case invalidDefinition
    case unsupportedNaturalLanguage
    case duplicateID
    case notFound
}

actor RoutineMacroStore {
    private let store: LocalStore
    private let filename: String
    private var loaded = false
    private var routines: [UUID: RoutineMacro] = [:]

    init(store: LocalStore = .shared, filename: String = "routine-macros.json") {
        self.store = store
        self.filename = filename
    }

    func all() async throws -> [RoutineMacro] {
        try await loadIfNeeded()
        return routines.values.sorted { $0.createdAt < $1.createdAt }
    }

    func save(_ routine: RoutineMacro) async throws {
        try Self.validate(routine)
        try await loadIfNeeded()
        routines[routine.id] = routine
        try await persist()
    }

    func update(_ id: UUID, _ change: @Sendable (inout RoutineMacro) -> Void) async throws {
        try await loadIfNeeded()
        guard var routine = routines[id] else { throw RoutineMacroError.notFound }
        change(&routine)
        routine.revision += 1
        routine.updatedAt = Date()
        try Self.validate(routine)
        routines[id] = routine
        try await persist()
    }

    func delete(_ id: UUID) async throws {
        try await loadIfNeeded()
        guard routines.removeValue(forKey: id) != nil else { throw RoutineMacroError.notFound }
        try await persist()
    }

    private func loadIfNeeded() async throws {
        guard !loaded else { return }
        let values = try await store.load([RoutineMacro].self, from: filename) ?? []
        routines = Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
        loaded = true
    }

    private func persist() async throws { try await store.save(Array(routines.values), as: filename) }

    static func validate(_ routine: RoutineMacro) throws {
        guard !routine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !routine.actions.isEmpty, routine.actions.count <= 16,
              Set(routine.actions.map(\.id)).count == routine.actions.count else {
            throw RoutineMacroError.invalidDefinition
        }
        let plan = DeterministicExecutionPlan(
            commandID: routine.id, intent: .multiStep, constraints: [],
            steps: routine.actions.map { .init(id: $0.id, capability: $0.capability, dependencies: $0.dependencies) },
            completionStepID: routine.actions.last!.id, aiInvocationCount: 0
        )
        do { _ = try plan.parallelGroups() } catch { throw RoutineMacroError.invalidDefinition }
    }
}

struct RoutineExecutionAuthorization: Sendable {
    let grantedPermissions: Set<String>
    let confirmedActionIDs: Set<String>
    static let none = Self(grantedPermissions: [], confirmedActionIDs: [])
}

enum RoutineExecutionResult: Equatable, Sendable {
    case noMatch
    case disabled
    case conditionsNotMet
    case duplicate
    case executed(CoordinationExecutionReport)
}

actor RoutineExecutionLedger {
    private let store: LocalStore
    private let filename: String
    private var loaded = false
    private var claimed: [String] = []

    init(store: LocalStore = .shared, filename: String = "routine-execution-ledger.json") {
        self.store = store; self.filename = filename
    }

    func claim(_ key: String) async throws -> Bool {
        if !loaded {
            claimed = try await store.load([String].self, from: filename) ?? []
            loaded = true
        }
        guard !claimed.contains(key) else { return false }
        claimed.append(key)
        if claimed.count > 512 { claimed.removeFirst(claimed.count - 512) }
        try await store.save(claimed, as: filename)
        return true
    }
}

struct RoutineMacroEngine: Sendable {
    let executor: DeterministicPlanExecutor
    let ledger: RoutineExecutionLedger

    init(executor: DeterministicPlanExecutor, ledger: RoutineExecutionLedger = .init()) {
        self.executor = executor; self.ledger = ledger
    }

    func makeRoutine(from text: String, now: Date = Date()) throws -> RoutineMacro {
        let normalized = text.lowercased().replacingOccurrences(of: "’", with: "'")
        guard normalized.contains("коли я кажу") else { throw RoutineMacroError.unsupportedNaturalLanguage }
        let phrase: String
        if let comma = normalized.firstIndex(of: ",") {
            phrase = String(normalized[normalized.index(normalized.startIndex, offsetBy: 12)..<comma]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else { throw RoutineMacroError.unsupportedNaturalLanguage }
        guard !phrase.isEmpty else { throw RoutineMacroError.unsupportedNaturalLanguage }
        var actions = [RoutineAction(id: "route", capability: .transport, dependencies: [], parameters: ["destination": phrase.contains("робот") ? "work" : "home"], requiredPermission: "location", risk: .informational)]
        if normalized.contains("час дороги") {
            actions.append(.init(id: "travel-time", capability: .transport, dependencies: ["route"], parameters: ["result": "travel_time"], requiredPermission: "location", risk: .informational))
        }
        if normalized.contains("зустріч") {
            actions.append(.init(id: "next-event", capability: .calendar, dependencies: [], parameters: ["query": "next_event"], requiredPermission: "calendar", risk: .informational))
        }
        if normalized.contains("магазин") || normalized.contains("покуп") {
            actions.append(.init(id: "store-along-route", capability: .candidateDiscovery, dependencies: ["route"], parameters: ["category": "store", "relation": "along_route"], requiredPermission: "location", risk: .informational))
        }
        return .init(id: UUID(), name: phrase, trigger: .exactPhrase(phrase), conditions: [.always], actions: actions, isEnabled: true, revision: 1, createdAt: now, updatedAt: now)
    }

    func execute(
        _ routine: RoutineMacro,
        phrase: String,
        eventID: String,
        context: [String: String] = [:],
        authorization: RoutineExecutionAuthorization = .none,
        operations: [String: CoordinationStepOperation]
    ) async throws -> RoutineExecutionResult {
        guard case let .exactPhrase(trigger) = routine.trigger,
              trigger.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == phrase.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) else { return .noMatch }
        guard routine.isEnabled else { return .disabled }
        guard routine.conditions.allSatisfy({ condition in
            switch condition {
            case .always: true
            case let .contextFlag(key, expected): context[key] == expected
            }
        }) else { return .conditionsNotMet }
        try RoutineMacroStore.validate(routine)
        let key = "\(routine.id.uuidString):\(routine.revision):\(eventID)"
        guard try await ledger.claim(key) else { return .duplicate }

        var guarded: [String: CoordinationStepOperation] = [:]
        for action in routine.actions {
            guarded[action.id] = {
                if let permission = action.requiredPermission,
                   !authorization.grantedPermissions.contains(permission) {
                    throw CoordinationOperationError.permissionDenied
                }
                if action.risk == .consequential && !authorization.confirmedActionIDs.contains(action.id) {
                    throw CoordinationOperationError.confirmationRequired
                }
                guard let operation = operations[action.id] else { throw RoutineMacroError.invalidDefinition }
                return try await operation()
            }
        }
        let plan = DeterministicExecutionPlan(commandID: routine.id, intent: .multiStep, constraints: [], steps: routine.actions.map { .init(id: $0.id, capability: $0.capability, dependencies: $0.dependencies) }, completionStepID: routine.actions.last!.id, aiInvocationCount: 0)
        return .executed(try await executor.execute(plan, operations: guarded))
    }
}
