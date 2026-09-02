import Testing
@testable import UniversalAssistant

@Suite("Deterministic typed execution plans")
struct DeterministicExecutionPlanTests {
    @Test func simpleKnownCommandUsesFastPathWithZeroAI() throws {
        let command = LocalCommandEngine().parse("Відкрий Telegram")
        let plan = try DeterministicExecutionPlanBuilder().plan(for: command)
        #expect(plan.aiInvocationCount == 0)
        #expect(try plan.parallelGroups().count == 2)
        #expect(plan.steps.first?.capability == .directAction)
    }

    @Test func travelModulesFormIndependentParallelGroupWithZeroAI() throws {
        let command = StructuredCommand(originalText: "travel", normalizedText: "travel", language: .en, intent: .travelPlan)
        let plan = try DeterministicExecutionPlanBuilder().plan(for: command)
        let groups = try plan.parallelGroups()
        #expect(plan.aiInvocationCount == 0)
        #expect(groups.first?.map(\.capability).contains(.location) == true)
        let providerGroup = try #require(groups.first { Set($0.map(\.capability)) == [.weather, .transport, .hotel] })
        #expect(providerGroup.count == 3)
    }

    @Test func calendarDeadlineIsARealPrerequisiteForTravelAndHotel() throws {
        let command = StructuredCommand(originalText: "travel", normalizedText: "travel", language: .en, intent: .travelPlan)
        let plan = try DeterministicExecutionPlanBuilder().plan(for: command)
        #expect(plan.steps.first { $0.capability == .transport }?.dependencies.contains("calendar") == true)
        #expect(plan.steps.first { $0.capability == .hotel }?.dependencies.contains("calendar") == true)
    }

    @Test func unresolvedCommandDoesNotGuessOrInvokeAIInsidePlanner() {
        let command = LocalCommandEngine().parse("незрозумілий запит")
        #expect(throws: ExecutionPlanError.unresolvedCommand) { try DeterministicExecutionPlanBuilder().plan(for: command) }
    }

    @Test func cyclesAreRejected() {
        let plan = DeterministicExecutionPlan(commandID: .init(), intent: .multiStep, constraints: [], steps: [
            .init(id: "a", capability: .calendar, dependencies: ["b"]),
            .init(id: "b", capability: .location, dependencies: ["a"])
        ], completionStepID: "b", aiInvocationCount: 0)
        #expect(throws: ExecutionPlanError.cyclicDependencies) { try plan.parallelGroups() }
    }
}
