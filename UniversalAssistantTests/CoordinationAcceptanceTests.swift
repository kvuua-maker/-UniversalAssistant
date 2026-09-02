import Foundation
import Testing
@testable import UniversalAssistant

private actor ConcurrencyProbe {
    private var active = 0
    private(set) var maximum = 0
    private(set) var cancelled = 0

    func begin() { active += 1; maximum = max(maximum, active) }
    func end() { active -= 1 }
    func cancellation() { cancelled += 1 }
}

private func acceptanceFact(_ id: String, value: String = "verified") -> ResultFact {
    .init(id: id, label: id, value: value, state: .verified,
          source: "acceptance_fixture", observedAt: Date(timeIntervalSince1970: 1), priority: 1)
}

@Suite("Deterministic coordination acceptance")
struct CoordinationAcceptanceTests {
    @Test func travelExecutesCalendarLocationWeatherTransportAndHotelWithZeroAI() async throws {
        let command = StructuredCommand(originalText: "travel", normalizedText: "travel", language: .en, intent: .travelPlan)
        let plan = try DeterministicExecutionPlanBuilder().plan(for: command)
        let probe = ConcurrencyProbe()
        var operations: [String: CoordinationStepOperation] = [:]
        for step in plan.steps {
            operations[step.id] = {
                if ["weather", "transport", "hotel"].contains(step.id) {
                    await probe.begin()
                    try await Task.sleep(for: .milliseconds(20))
                    await probe.end()
                }
                return acceptanceFact(step.id)
            }
        }
        let report = try await DeterministicPlanExecutor(maximumConcurrency: 3).execute(plan, operations: operations)
        #expect(report.aiInvocationCount == 0)
        #expect(["calendar", "location", "weather", "transport", "hotel"].allSatisfy { report.outcomes[$0] != nil })
        #expect(report.maximumObservedConcurrency == 3)
        #expect(await probe.maximum == 3)
    }

    @Test func providerFailureReturnsTruthfulPartialResultWithoutInventedValue() async throws {
        enum Failure: Error { case unavailable }
        let command = StructuredCommand(originalText: "travel", normalizedText: "travel", language: .en, intent: .travelPlan)
        let plan = try DeterministicExecutionPlanBuilder().plan(for: command)
        var operations = Dictionary(uniqueKeysWithValues: plan.steps.map { step in
            (step.id, { acceptanceFact(step.id) } as CoordinationStepOperation)
        })
        operations["hotel"] = { throw Failure.unavailable }
        let report = try await DeterministicPlanExecutor().execute(plan, operations: operations)
        #expect(report.outcomes["weather"] == .verified(acceptanceFact("weather")))
        #expect(report.outcomes["hotel"] == .unavailable(.providerFailure))
    }

    @Test func sufficientResultCancelsObsoleteParallelWork() async throws {
        let plan = DeterministicExecutionPlan(commandID: .init(), intent: .multiStep, constraints: [], steps: [
            .init(id: "fast", capability: .weather, dependencies: []),
            .init(id: "slow", capability: .hotel, dependencies: [])
        ], completionStepID: "fast", aiInvocationCount: 0)
        let probe = ConcurrencyProbe()
        let operations: [String: CoordinationStepOperation] = [
            "fast": { try await Task.sleep(for: .milliseconds(10)); return acceptanceFact("fast") },
            "slow": {
                do { try await Task.sleep(for: .seconds(2)); return acceptanceFact("slow") }
                catch { await probe.cancellation(); throw error }
            }
        ]
        let report = try await DeterministicPlanExecutor(maximumConcurrency: 2).execute(
            plan, operations: operations,
            stopWhen: { $0["fast"] == .verified(acceptanceFact("fast")) }
        )
        #expect(report.outcomes["fast"] == .verified(acceptanceFact("fast")))
        #expect(report.outcomes["slow"] == .unavailable(.cancelled))
        #expect(await probe.cancelled == 1)
    }
}
