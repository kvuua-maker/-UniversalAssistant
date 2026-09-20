import Foundation
import Testing

@testable import UniversalAssistant

private actor JobsProviderProbe: JobDiscoveryProvider {
  let id: String
  let tier: JobResultTier
  let results: [JobDiscoveryResult]
  private(set) var calls = 0
  init(id: String, tier: JobResultTier, results: [JobDiscoveryResult]) {
    self.id = id
    self.tier = tier
    self.results = results
  }
  func search(_ intent: GenericIntent) async throws -> [JobDiscoveryResult] {
    calls += 1
    return results
  }
}
private func discoveryJob(
  _ id: String, tier: JobResultTier, salary: Decimal? = 50_000, evidence: String? = nil
) -> JobDiscoveryResult {
  .init(
    id: id, title: "Водій", employer: "ТОВ Робота \(id)", locality: "Київ", salaryMinimum: salary,
    salaryMaximum: salary, currency: salary == nil ? nil : "UAH", salaryBasis: "gross",
    employmentType: "повна", publishedAt: .now, observedAt: .now, sourceName: id,
    sourceURL: URL(string: "https://example.test/jobs/\(id)")!, tier: tier,
    commercialEvidenceID: evidence, confidence: 0.9)
}
private func jobsIntent() throws -> GenericIntent {
  try GenericIntentParser().parse("Знайди роботу водієм у Києві від 40 000 грн")
}
@Suite("Jobs discovery and native result")
struct JobsDiscoveryEngineTests {
  @Test func stateEmploymentXMLParsesRealFieldsWithoutInventingVacancyData() throws {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <jobs><job id="job-1"><name>Водій</name><region>Київ</region>
    <link>https://example.test/state/job-1</link>
    <description><![CDATA[Назва підприємства: ТОВ Перевізник
    Заробітна плата (усього): 50000
    Характер виконуваної роботи: Постійний]]></description></job></jobs>
    """
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let jobs = StateEmploymentXMLParser.parse(Data(xml.utf8), sourceDate: date)
    #expect(jobs.count == 1)
    #expect(jobs.first?.title == "Водій")
    #expect(jobs.first?.locality == "Київ")
    #expect(jobs.first?.salaryMinimum == 50_000)
    #expect(jobs.first?.sourceName == "Державна служба зайнятості")
    #expect(jobs.first?.observedAt == date)
  }

  @Test func ourJobsSatisfyRequestWithoutCallingExternalFallback() async throws {
    let direct = JobsProviderProbe(
      id: "direct", tier: .directEmployer,
      results: [
        discoveryJob("1", tier: .directEmployer), discoveryJob("2", tier: .directEmployer),
        discoveryJob("3", tier: .directEmployer),
      ])
    let fallback = JobsProviderProbe(
      id: "fallback", tier: .externalFallback, results: [discoveryJob("4", tier: .externalFallback)]
    )
    let result = try await JobDiscoveryEngine(providers: [direct, fallback]).search(jobsIntent())
    #expect(await fallback.calls == 0)
    #expect(result.aiInvocationCount == 0)
    #expect(result.facts.count == 3)
  }
  @Test func insufficientOurJobsUsesTruthfulExternalHandoffWithoutRevenueClaim() async throws {
    let direct = JobsProviderProbe(
      id: "direct", tier: .directEmployer, results: [discoveryJob("1", tier: .directEmployer)])
    let fallback = JobsProviderProbe(
      id: "fallback", tier: .externalFallback, results: [discoveryJob("2", tier: .externalFallback)]
    )
    let result = try await JobDiscoveryEngine(providers: [direct, fallback]).search(jobsIntent())
    #expect(await fallback.calls == 1)
    #expect(result.actions.allSatisfy { $0.title == "Відкрити вакансію" && $0.kind == .open })
  }
  @Test func commercialWithoutCurrentEvidenceIsExcludedAndUnknownSalaryDoesNotPassMinimum()
    async throws
  {
    let provider = JobsProviderProbe(
      id: "commercial", tier: .verifiedCommercial,
      results: [
        discoveryJob("no-evidence", tier: .verifiedCommercial),
        discoveryJob(
          "unknown-salary", tier: .verifiedCommercial, salary: nil, evidence: "contract"),
      ])
    await #expect(throws: JobDiscoveryError.noVerifiedResults) {
      try await JobDiscoveryEngine(providers: [provider]).search(jobsIntent())
    }
  }
  @Test func sourceRegistryNeverClaimsUnauditedAPIOrPartnership() {
    #expect(UkrainianJobSourceRegistry.audited.count >= 7)
    #expect(UkrainianJobSourceRegistry.audited.allSatisfy { !$0.authenticatedAPI })
    #expect(
      UkrainianJobSourceRegistry.audited.contains {
        $0.id == "dcz" && $0.mechanism == "official_public_handoff"
      })
  }
}
