import Foundation

enum ExecutionCapability: String, Codable, Sendable {
    case voice, command, directAction, relativeDate, calendar, location, places, route, candidateDiscovery
    case weather, transport, hotel, deterministicCompose
}
enum ConstraintStrength: String, Codable, Sendable { case hard, soft }
struct ResolvedPlanConstraint: Equatable, Codable, Sendable {
    let key: String; let value: String; let strength: ConstraintStrength; let source: String
}
struct ExecutionPlanStep: Identifiable, Equatable, Codable, Sendable {
    let id: String; let capability: ExecutionCapability; let dependencies: Set<String>
}
struct DeterministicExecutionPlan: Equatable, Codable, Sendable {
    let commandID: UUID
    let intent: CommandIntent
    let constraints: [ResolvedPlanConstraint]
    let steps: [ExecutionPlanStep]
    let completionStepID: String
    let aiInvocationCount: Int

    func parallelGroups() throws -> [[ExecutionPlanStep]] {
        guard aiInvocationCount == 0, !steps.isEmpty,
              Set(steps.map(\.id)).count == steps.count,
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
    /// Minimal module path for a command. This is planning metadata over the
    /// existing capabilities, not a second router or provider registry.
    func activationPath(for command: StructuredCommand) throws -> [ExecutionCapability] {
        guard !command.needsClarification, command.intent != .unknown else { throw ExecutionPlanError.unresolvedCommand }
        switch command.intent {
        case .placeSearch:
            return [.voice, .command, .location, .places, .route]
        case .navigation:
            return [.voice, .command, .location, .route]
        case .calendarCreate, .calendarQuery, .calendarUpdate, .calendarDelete:
            return [.voice, .command, .calendar]
        case .travelPlan, .multiStep:
            return [.voice, .command, .relativeDate, .calendar, .location, .candidateDiscovery, .weather, .transport, .hotel, .deterministicCompose]
        default:
            return [.voice, .command, .directAction]
        }
    }

    func plan(for command: StructuredCommand) throws -> DeterministicExecutionPlan {
        guard !command.needsClarification, command.intent != .unknown else { throw ExecutionPlanError.unresolvedCommand }
        if command.intent == .travelPlan || command.intent == .multiStep {
            return travelPlan(command)
        }
        let steps = [ExecutionPlanStep(id: "direct", capability: .directAction, dependencies: []),
                     ExecutionPlanStep(id: "compose", capability: .deterministicCompose, dependencies: ["direct"])]
        return .init(commandID: command.id, intent: command.intent, constraints: constraints(command),
                     steps: steps, completionStepID: "compose", aiInvocationCount: 0)
    }

    private func travelPlan(_ command: StructuredCommand) -> DeterministicExecutionPlan {
        let steps = [
            ExecutionPlanStep(id: "date", capability: .relativeDate, dependencies: []),
            ExecutionPlanStep(id: "calendar", capability: .calendar, dependencies: ["date"]),
            ExecutionPlanStep(id: "location", capability: .location, dependencies: []),
            ExecutionPlanStep(id: "candidates", capability: .candidateDiscovery, dependencies: ["date", "location"]),
            ExecutionPlanStep(id: "weather", capability: .weather, dependencies: ["candidates"]),
            ExecutionPlanStep(id: "transport", capability: .transport, dependencies: ["calendar", "candidates"]),
            ExecutionPlanStep(id: "hotel", capability: .hotel, dependencies: ["calendar", "candidates"]),
            ExecutionPlanStep(id: "compose", capability: .deterministicCompose, dependencies: ["weather", "transport", "hotel"])
        ]
        return .init(commandID: command.id, intent: command.intent, constraints: constraints(command),
                     steps: steps, completionStepID: "compose", aiInvocationCount: 0)
    }

    private func constraints(_ command: StructuredCommand) -> [ResolvedPlanConstraint] {
        var values: [ResolvedPlanConstraint] = []
        if let price = command.constraints.maximumPrice {
            values.append(.init(key: "maximumPrice", value: "\(price) \(command.constraints.currency ?? "UNKNOWN")",
                                strength: .hard, source: "explicit_command"))
        }
        return values
    }
}
