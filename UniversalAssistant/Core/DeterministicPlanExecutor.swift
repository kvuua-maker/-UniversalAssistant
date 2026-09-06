import Foundation

typealias CoordinationStepOperation = @Sendable () async throws -> ResultFact

enum CoordinationStepFailure: String, Codable, Equatable, Sendable {
    case providerFailure
    case timeout
    case cancelled
    case operationUnavailable
    case permissionDenied
    case confirmationRequired
}

enum CoordinationOperationError: Error, Equatable, Sendable {
    case permissionDenied
    case confirmationRequired
}

enum CoordinationStepOutcome: Equatable, Sendable {
    case verified(ResultFact)
    case unavailable(CoordinationStepFailure)
}

struct CoordinationExecutionReport: Equatable, Sendable {
    let outcomes: [String: CoordinationStepOutcome]
    let maximumObservedConcurrency: Int
    let aiInvocationCount: Int
}

enum DeterministicPlanExecutorError: Error, Equatable, Sendable {
    case invalidConcurrency
}

actor DeterministicPlanExecutor {
    private let maximumConcurrency: Int
    private let operationTimeout: Duration

    init(maximumConcurrency: Int = 3, operationTimeout: Duration = .seconds(10)) throws {
        guard maximumConcurrency > 0, operationTimeout > .zero else {
            throw DeterministicPlanExecutorError.invalidConcurrency
        }
        self.maximumConcurrency = maximumConcurrency
        self.operationTimeout = operationTimeout
    }

    func execute(
        _ plan: DeterministicExecutionPlan,
        operations: [String: CoordinationStepOperation],
        stopWhen: (@Sendable ([String: CoordinationStepOutcome]) -> Bool)? = nil
    ) async throws -> CoordinationExecutionReport {
        let groups = try plan.parallelGroups()
        var outcomes: [String: CoordinationStepOutcome] = [:]
        var maximumObservedConcurrency = 0

        for group in groups {
            let result = await execute(group, operations: operations, prior: outcomes, stopWhen: stopWhen)
            outcomes.merge(result.outcomes) { _, new in new }
            maximumObservedConcurrency = max(maximumObservedConcurrency, result.maximumObservedConcurrency)
        }
        return .init(outcomes: outcomes, maximumObservedConcurrency: maximumObservedConcurrency,
                     aiInvocationCount: plan.aiInvocationCount)
    }

    private func execute(
        _ steps: [ExecutionPlanStep],
        operations: [String: CoordinationStepOperation],
        prior: [String: CoordinationStepOutcome],
        stopWhen: (@Sendable ([String: CoordinationStepOutcome]) -> Bool)?
    ) async -> (outcomes: [String: CoordinationStepOutcome], maximumObservedConcurrency: Int) {
        await withTaskGroup(of: (String, CoordinationStepOutcome).self) { group in
            let blocked = steps.filter { step in step.dependencies.contains { dependency in
                guard let outcome = prior[dependency] else { return true }
                if case .verified = outcome { return false }
                return true
            } }
            let runnable = steps.filter { step in !blocked.contains(where: { $0.id == step.id }) }
            var iterator = runnable.makeIterator()
            var groupOutcomes: [String: CoordinationStepOutcome] = Dictionary(uniqueKeysWithValues: blocked.map { ($0.id, .unavailable(.operationUnavailable)) })
            var active = 0
            var maximumObserved = 0

            func submit(_ step: ExecutionPlanStep) {
                active += 1
                maximumObserved = max(maximumObserved, active)
                let operation = operations[step.id]
                let timeout = operationTimeout
                group.addTask {
                    guard let operation else { return (step.id, .unavailable(.operationUnavailable)) }
                    return (step.id, await Self.run(operation, timeout: timeout))
                }
            }

            for _ in 0..<min(maximumConcurrency, runnable.count) {
                if let step = iterator.next() { submit(step) }
            }
            while let (id, outcome) = await group.next() {
                active -= 1
                groupOutcomes[id] = outcome
                var aggregate = prior
                aggregate.merge(groupOutcomes) { _, new in new }
                if stopWhen?(aggregate) == true {
                    group.cancelAll()
                } else if let step = iterator.next() {
                    submit(step)
                }
            }
            while let step = iterator.next() {
                groupOutcomes[step.id] = .unavailable(.cancelled)
            }
            return (groupOutcomes, maximumObserved)
        }
    }

    private static func run(_ operation: @escaping CoordinationStepOperation, timeout: Duration) async -> CoordinationStepOutcome {
        do {
            return try await withThrowingTaskGroup(of: ResultFact.self) { group in
                group.addTask { try await operation() }
                group.addTask { try await Task.sleep(for: timeout); throw StepError.timeout }
                defer { group.cancelAll() }
                return .verified(try await group.next()!)
            }
        } catch is CancellationError {
            return .unavailable(.cancelled)
        } catch StepError.timeout {
            return .unavailable(.timeout)
        } catch CoordinationOperationError.permissionDenied {
            return .unavailable(.permissionDenied)
        } catch CoordinationOperationError.confirmationRequired {
            return .unavailable(.confirmationRequired)
        } catch {
            return .unavailable(.providerFailure)
        }
    }

    private enum StepError: Error { case timeout }
}
