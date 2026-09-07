import Foundation

enum ExecutionCapability: String, Codable, Sendable {
    case voice, command, directAction, typedCommand, relativeDate, calendar, location, places, route, candidateDiscovery
    case weather, transport, hotel, deterministicCompose
}
enum ConstraintStrength: String, Codable, Sendable { case hard, soft }
struct ResolvedPlanConstraint: Equatable, Codable, Sendable {
    let key: String; let value: String; let strength: ConstraintStrength; let source: String
}
struct ExecutionPlanStep: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let capability: ExecutionCapability
    let dependencies: Set<String>
    let command: StructuredCommand?
    init(id: String, capability: ExecutionCapability, dependencies: Set<String>, command: StructuredCommand? = nil) {
        self.id = id; self.capability = capability; self.dependencies = dependencies; self.command = command
    }
}
struct DeterministicExecutionPlan: Equatable, Codable, Sendable {
    let commandID: UUID
    let intent: CommandIntent
    let constraints: [ResolvedPlanConstraint]
    let steps: [ExecutionPlanStep]
    let completionStepID: String
    let aiInvocationCount: Int

    func parallelGroups() throws -> [[ExecutionPlanStep]] {
        guard aiInvocationCount == 0, !steps.isEmpty, Set(steps.map(\.id)).count == steps.count,
              steps.contains(where: { $0.id == completionStepID }) else { throw ExecutionPlanError.invalidPlan }
        let ids = Set(steps.map(\.id))
        guard steps.allSatisfy({ $0.dependencies.isSubset(of: ids) && !$0.dependencies.contains($0.id) }) else { throw ExecutionPlanError.invalidPlan }
        var remaining = Dictionary(uniqueKeysWithValues: steps.map { ($0.id, $0) })
        var completed: Set<String> = [], groups: [[ExecutionPlanStep]] = []
        while !remaining.isEmpty {
            let ready = remaining.values.filter { $0.dependencies.isSubset(of: completed) }.sorted { $0.id < $1.id }
            guard !ready.isEmpty else { throw ExecutionPlanError.cyclicDependencies }
            groups.append(ready)
            ready.forEach { remaining.removeValue(forKey: $0.id); completed.insert($0.id) }
        }
        return groups
    }
}
enum ExecutionPlanError: Error, Equatable, Sendable { case invalidPlan, cyclicDependencies, unresolvedCommand }

struct DeterministicExecutionPlanBuilder: Sendable {
    private let parser: any CommandParsing
    init(parser: any CommandParsing = LocalCommandEngine()) { self.parser = parser }

    func activationPath(for command: StructuredCommand) throws -> [ExecutionCapability] {
        guard !command.needsClarification, command.intent != .unknown else { throw ExecutionPlanError.unresolvedCommand }
        switch command.intent {
        case .placeSearch: return [.voice, .command, .location, .places, .route]
        case .navigation: return [.voice, .command, .location, .route]
        case .calendarCreate, .calendarQuery, .calendarUpdate, .calendarDelete: return [.voice, .command, .calendar]
        case .travelPlan, .multiStep: return [.voice, .command, .directAction]
        default: return [.voice, .command, .directAction]
        }
    }

    func plan(for command: StructuredCommand) throws -> DeterministicExecutionPlan {
        guard !command.needsClarification, command.intent != .unknown else { throw ExecutionPlanError.unresolvedCommand }
        if command.intent == .multiStep, let typed = typedPlan(command) { return typed }
        if command.intent == .travelPlan || command.intent == .multiStep { return travelPlan(command) }
        let steps = [ExecutionPlanStep(id: "direct", capability: concreteCapability(for: command.intent), dependencies: [], command: command)]
        return .init(commandID: command.id, intent: command.intent, constraints: constraints(command), steps: steps, completionStepID: "direct", aiInvocationCount: 0)
    }

    private func typedPlan(_ command: StructuredCommand) -> DeterministicExecutionPlan? {
        let split = CompoundCommandClauses.split(command.originalText)
        var commands = split.compactMap { clause -> StructuredCommand? in
            let parsed = parser.parse(clause)
            if isRouteInstruction(clause) { return derived(parsed, intent: .navigation) }
            if isStandalonePresentationVerb(parsed.normalizedText) { return nil }
            return !parsed.needsClarification && parsed.intent != .unknown && parsed.intent != .multiStep ? parsed : nil
        }
        let hasRouteClause = commands.contains { [.navigation, .routeSearch, .transportRoute].contains($0.intent) }
        if hasRouteClause {
            commands = commands.map { value in
                let storefront = ["магазин", "крамниц", "store", "shop"].contains(where: value.normalizedText.contains)
                if storefront { return derived(value, intent: .placeSearch) }
                if value.intent == .transportRoute { return derived(value, intent: .navigation) }
                return value
            }
        }
        guard commands.count >= 2 else { return nil }
        var steps: [ExecutionPlanStep] = []
        var lastByIntent: [CommandIntent: String] = [:]
        for (index, subcommand) in commands.enumerated() {
            let id = String(format: "step-%02d-%@", index + 1, subcommand.intent.rawValue)
            var dependencies: Set<String> = []
            switch subcommand.intent {
            case .contactCall, .messageCompose:
                if let prior = lastByIntent[.contactLookup] { dependencies.insert(prior) }
            case .navigation, .routeSearch:
                if let prior = lastByIntent[.placeSearch] { dependencies.insert(prior) }
            case .routeAwareSearch:
                if let prior = lastByIntent[.navigation] ?? lastByIntent[.routeSearch] { dependencies.insert(prior) }
            case .calendarUpdate, .calendarDelete:
                if let prior = lastByIntent[.calendarQuery] { dependencies.insert(prior) }
            case .reminderComplete, .reminderDelete:
                if let prior = lastByIntent[.reminderQuery] { dependencies.insert(prior) }
            case .translation:
                if let prior = lastByIntent[.cameraCapture] { dependencies.insert(prior) }
            default: break
            }
            steps.append(.init(id: id, capability: concreteCapability(for: subcommand.intent), dependencies: dependencies, command: subcommand))
            lastByIntent[subcommand.intent] = id
        }
        guard let completionStepID = steps.last?.id else { return nil }
        return .init(commandID: command.id, intent: command.intent, constraints: constraints(command), steps: steps, completionStepID: completionStepID, aiInvocationCount: 0)
    }

    private func travelPlan(_ command: StructuredCommand) -> DeterministicExecutionPlan {
        let steps = [
            ExecutionPlanStep(id: "date", capability: .relativeDate, dependencies: []),
            ExecutionPlanStep(id: "calendar", capability: .calendar, dependencies: ["date"]),
            ExecutionPlanStep(id: "location", capability: .location, dependencies: []),
            ExecutionPlanStep(id: "candidates", capability: .candidateDiscovery, dependencies: ["date", "location"]),
            ExecutionPlanStep(id: "weather", capability: .weather, dependencies: ["candidates"]),
            ExecutionPlanStep(id: "transport", capability: .transport, dependencies: ["calendar", "candidates"]),
            ExecutionPlanStep(id: "hotel", capability: .hotel, dependencies: ["calendar", "candidates"])
        ]
        return .init(commandID: command.id, intent: command.intent, constraints: constraints(command), steps: steps, completionStepID: "hotel", aiInvocationCount: 0)
    }

    private func isRouteInstruction(_ clause: String) -> Bool {
        let value = clause.lowercased(with: .current)
        let routeVerb = ["доїхати", "доехать", "дістатися", "добраться", "navigate", "directions", "route"].contains(where: value.contains)
        let routeFraming = ["як ", "маршрут", "проклади", "покажи", "how ", "route", "directions"].contains(where: value.contains)
        return routeVerb && routeFraming
    }

    private func isStandalonePresentationVerb(_ value: String) -> Bool {
        ["покажи", "показати", "покажи як", "show", "show me", "покажи мне"].contains(value.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)))
    }

    private func derived(_ command: StructuredCommand, intent: CommandIntent) -> StructuredCommand {
        .init(id: command.id, originalText: command.originalText, normalizedText: command.normalizedText, language: command.language, intent: intent, entities: command.entities, constraints: command.constraints, risk: command.risk, needsClarification: false)
    }

    private func concreteCapability(for intent: CommandIntent) -> ExecutionCapability {
        switch intent {
        case .calendarCreate, .calendarQuery, .calendarUpdate, .calendarDelete, .reminderCreate, .reminderQuery, .reminderComplete, .reminderDelete, .shoppingList, .undo: .calendar
        case .placeSearch, .restaurantSearch, .serviceSearch: .places
        case .navigation, .routeSearch, .routeAwareSearch: .route
        case .weather: .weather
        default: .directAction
        }
    }

    private func constraints(_ command: StructuredCommand) -> [ResolvedPlanConstraint] {
        var values: [ResolvedPlanConstraint] = []
        if let price = command.constraints.maximumPrice {
            values.append(.init(key: "maximumPrice", value: "\(price) \(command.constraints.currency ?? "UNKNOWN")", strength: .hard, source: "explicit_command"))
        }
        return values
    }
}
