import Foundation
import Testing

@testable import UniversalAssistantServer

@Suite("Jobs residual policy behavior")
struct JobsPolicyExtensionsTests {
  @Test func blockSavedStateAndAppealPersistAcrossRestart() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      .appendingPathComponent("policy.json")
    let candidate = UUID()
    let employer = UUID()
    let vacancy = jobVacancy(employer, state: .active)
    let enforcement: JobsEnforcement
    do {
      let store = try JobsPolicyStore(persistenceURL: file)
      try await store.block(candidateID: candidate, employerID: employer)
      #expect(await !store.mayContact(candidateID: candidate, employerID: employer))
      let first = try await store.saveJob(accountID: candidate, vacancy: vacancy)
      #expect(try await store.saveJob(accountID: candidate, vacancy: vacancy).id == first.id)
      enforcement = try await store.enforce(
        employerID: employer, state: .suspended, reason: "credible_phishing", actor: "moderator",
        evidence: ["report-1"])
      _ = try await store.appeal(
        enforcementID: enforcement.id, employerID: employer, reason: "review evidence",
        actor: "employer")
    }
    let restored = try JobsPolicyStore(persistenceURL: file)
    #expect(await !restored.mayContact(candidateID: candidate, employerID: employer))
    #expect(await restored.savedJobs(accountID: candidate).count == 1)
  }

  @Test func interviewIsProposalUntilCandidateConfirmationAndHTTPSIsRequired() async throws {
    let store = try JobsPolicyStore()
    await #expect(throws: JobsPolicyError.invalidURL) {
      try await store.proposeInterview(
        applicationID: UUID(), proposedAt: .now, locationName: nil,
        onlineURL: URL(string: "http://unsafe.test"))
    }
    let proposal = try await store.proposeInterview(
      applicationID: UUID(), proposedAt: .now, locationName: "Офіс", onlineURL: nil)
    #expect(proposal.candidateAccepted == nil && proposal.calendarEventReference == nil)
    await #expect(throws: JobsPolicyError.candidateConfirmationRequired) {
      try await store.confirmInterview(
        proposal.id, candidateConfirmed: false, calendarEventReference: nil)
    }
    #expect(
      try await store.confirmInterview(
        proposal.id, candidateConfirmed: true, calendarEventReference: "calendar-event"
      ).calendarEventReference == "calendar-event")
  }

  @Test func promotionAndCommercialEligibilityFailClosed() throws {
    let employer = UUID()
    let active = jobVacancy(employer, state: .active)
    let now = Date()
    let promotion = JobsPromotion(
      id: UUID(), vacancyID: active.id, employerID: employer, entitlementOperationID: "promotion-1",
      startsAt: now.addingTimeInterval(-10), endsAt: now.addingTimeInterval(10), stoppedAt: nil)
    #expect(promotion.isActive(vacancy: active, at: now))
    #expect(!promotion.isActive(vacancy: jobVacancy(employer, state: .closed), at: now))
    let source = JobsCommercialSource(
      id: "provider", displayName: "Provider", commercialModel: "fixed",
      evidenceReference: "contract-v1", effectiveAt: now.addingTimeInterval(-10),
      expiresAt: now.addingTimeInterval(10), territories: ["UA"], capabilities: ["vacancy_search"],
      actionURL: URL(string: "https://example.test")!, suspended: false)
    #expect(source.isEligible(at: now, territory: "UA", capability: "vacancy_search"))
    #expect(
      !source.isEligible(
        at: now.addingTimeInterval(20), territory: "UA", capability: "vacancy_search"))
  }

  @Test func runtimePricingQuotaAndRetentionAreConfigurationNotHardcodedPolicy() throws {
    let config = try JobsRuntimeConfiguration(
      publicationPriceMinorUnits: 100, promotionPriceMinorUnits: 25, candidateSearchQuota: 10,
      invitationQuota: 5, pageSize: 25
    ).validated()
    #expect(config.pageSize == 25)
    #expect(throws: JobsError.invalid) {
      try JobsRuntimeConfiguration(
        publicationPriceMinorUnits: -1, promotionPriceMinorUnits: 0, candidateSearchQuota: 1,
        invitationQuota: 1, pageSize: 500
      ).validated()
    }
    let retention = JobsRetentionPolicy(
      profileDays: 30, applicationDays: 365, cvDays: 30, billingAuditDays: 2555,
      fraudEvidenceDays: 365)
    #expect(retention.retentionDays(for: "billing") == 2555)
    #expect(retention.retentionDays(for: "unknown") == nil)
  }
}
