import Foundation

typealias ProductionStepOperations = [String: CoordinationStepOperation]
typealias ProductionStepOperationFactory = @MainActor @Sendable (StructuredCommand, DeterministicExecutionPlan) -> ProductionStepOperations

@MainActor
final class ProductionMultiStepCoordinator {
    private let operationFactory: ProductionStepOperationFactory
    private var completedCommandIDs: Set<UUID> = []

    init(operationFactory: @escaping ProductionStepOperationFactory = { _, _ in [:] }) {
        self.operationFactory = operationFactory
    }

    func execute(_ command: StructuredCommand) async throws -> DeterministicResult {
        guard !completedCommandIDs.contains(command.id) else { throw CanonicalCapabilityExecutionError.unavailable("duplicate_multi_step_command") }
        let plan = try DeterministicExecutionPlanBuilder().plan(for: command)
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
