import Testing

@testable import UniversalAssistant

@Suite("Golden Jobs journeys")
struct JobsGoldenJourneyTests {
  @Test func corpusIsCompleteStableAndHasConsequentialConfirmations() throws {
    let journeys = JobsGoldenJourneyCatalog.canonical
    #expect(journeys.count == 15)
    #expect(Set(journeys.map(\.id)) == Set("ABCDEFGHIJKLMNO".map(String.init)))
    let consequential: Set<JobsGoldenOutcome> = [
      .internalApplication, .published, .invitation, .watch, .interviewProposal, .complaintRecorded,
      .protectiveReview,
    ]
    let confirmationPolicyHolds = journeys.filter { consequential.contains($0.expected) }
      .allSatisfy(\.requiresConfirmation)
    #expect(confirmationPolicyHolds)
  }
  @Test func naturalCandidateJourneyCompilesToTypedJobsIntentWithoutAI() throws {
    let intent = try GenericIntentParser().parse(JobsGoldenJourneyCatalog.canonical[0].request)
    #expect(intent.domain == "jobs")
    #expect(intent.location?.locality == "Київ")
    #expect(intent.money?.minimum == 50_000)
    #expect(intent.money?.currency == "UAH")
  }
  @Test func externalJourneysRequireTruthfulHandoffNotFalseApplication() {
    let external = JobsGoldenJourneyCatalog.canonical.filter {
      [.truthfulFallback, .externalHandoff].contains($0.expected)
    }
    #expect(external.count == 2)
    #expect(external.allSatisfy { !$0.requiresConfirmation })
  }
}
