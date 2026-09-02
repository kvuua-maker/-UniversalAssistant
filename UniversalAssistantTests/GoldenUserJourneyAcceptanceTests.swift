import Testing
@testable import UniversalAssistant

@Suite("Golden user journey acceptance") struct GoldenUserJourneyAcceptanceTests {
    @Test func corpusContainsOneHundredDistinctFullySpecifiedJourneys() {
        let journeys = GoldenUserJourneyCatalog.journeys
        #expect(journeys.count == 100); #expect(Set(journeys.map(\.id)).count == 100)
        #expect(journeys.allSatisfy { !$0.input.isEmpty && !$0.requiredCapabilities.isEmpty && !$0.truthAndSourceRequirement.isEmpty && !$0.sideEffectRule.isEmpty && !$0.expectedUIResult.isEmpty && !$0.failureBehavior.isEmpty && !$0.evidenceTest.isEmpty })
    }

    @Test func allLocallyExecutableCommandPathsProduceExpectedTypedOutcome() {
        let executions = GoldenUserJourneyCatalog.journeys.filter { $0.verification == .executableLocal }.map(GoldenJourneyRunner().execute)
        #expect(executions.count == 35)
        let failures = executions.filter { $0.status != .pass || $0.failureReason != nil || $0.recognizedText.isEmpty || $0.actualResultOrAction.isEmpty }
        #expect(failures.isEmpty)
        #expect(executions.allSatisfy { $0.latencyMilliseconds >= 0 })
    }

    @Test func liveJourneysRemainTruthfullySeparatedFromLocalPasses() {
        let live = GoldenUserJourneyCatalog.journeys.filter { $0.verification == .readyForLiveVerification }
        #expect(live.count == 65)
        #expect(live.allSatisfy { !$0.truthAndSourceRequirement.isEmpty && !$0.failureBehavior.isEmpty })
    }

    @Test func journeyMetricsAndBaselinesAreExecutableAndBounded() {
        let executions = GoldenUserJourneyCatalog.journeys.map(GoldenJourneyRunner().execute)
        let noExtraQuestionRate = Double(executions.filter { $0.taps == 0 }.count) / Double(executions.count)
        #expect(noExtraQuestionRate > 0.5)
        #expect(GoldenUserJourneyCatalog.journeys.allSatisfy { $0.manualBaselineSteps > 0 })
        #expect(GoldenUserJourneyCatalog.journeys.allSatisfy { $0.genericAIBaselineSteps == nil || $0.genericAIBaselineSteps! > 0 })
    }
}
