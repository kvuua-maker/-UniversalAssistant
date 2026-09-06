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
