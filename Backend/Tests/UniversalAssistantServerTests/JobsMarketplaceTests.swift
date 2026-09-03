import Foundation
import Testing

@testable import UniversalAssistantServer

private func jobEmployer(_ id: UUID) -> PartnerOnboardingRecord {
  .init(
    partnerID: id,
    draft: .init(
      legalName: "Employer", registrationReference: "UA-1", contactEmail: "hr@example.test",
      category: "jobs", countryCode: "UA", integrationLevel: .basicProfile), state: .active,
    verificationEvidence: [], technicalValidationPassed: true, agreementReference: "agreement-v1",
    approvalRecorded: true, auditTrail: [])
}
private func jobSalary() -> JobSalary {
  .init(
    minimum: 40_000, maximum: 60_000, currency: "UAH", period: .monthly, basis: .gross,
    guaranteed: 40_000, variableDescription: nil)
}
func jobVacancy(
  _ employer: UUID, tier: JobsSourceTier = .directPaidEmployer, state: VacancyState = .draft,
  text: String = "Безпечна вакансія"
) -> JobVacancy {
  let now = Date()
  return .init(
    id: UUID(), employerID: employer, externalID: nil, sourceProviderID: nil, role: "Водій",
    details: text, locality: "Київ", remoteMode: .onsite, salary: jobSalary(),
    employmentType: "повна", schedule: "денна", experience: nil,
    criteria: [.init(value: "посвідчення B", kind: .mustHave)], languages: ["uk"], licenses: ["B"],
    positions: 1, cvRequirement: .optional, screening: [], applicationURL: nil, sourceTier: tier,
    commercialEvidenceID: tier == .commercialPartner ? "contract-v1" : nil, status: state,
    createdAt: now, updatedAt: now, publishedAt: state == .active ? now : nil,
    expiresAt: now.addingTimeInterval(86_400), version: 1, moderationReasons: [], audit: [])
}
private func jobRequest() -> JobSearchRequest {
  .init(
    role: "водій", locality: "Київ", remoteModes: [], minimumSalary: 40_000, currency: "UAH",
    employmentType: nil, scheduleExclusions: [], mustHave: ["посвідчення"], preferred: [], limit: 2)
}
private actor JobCallCounter {
  var value = 0
  func hit() { value += 1 }
}
@Suite("Jobs Marketplace employment core") struct JobsMarketplaceTests {
  @Test func verifiedBusinessEntitlementModerationAndRetryAreExact() async throws {
    let employer = UUID()
    let ledger = try JobsEntitlementLedger()
    try await ledger.credit(
      employerID: employer, kind: .vacancyPublication, quantity: 1, paymentEventID: "payment")
    try await ledger.credit(
      employerID: employer, kind: .vacancyPublication, quantity: 1, paymentEventID: "payment")
    #expect(await ledger.available(employerID: employer, kind: .vacancyPublication) == 1)
    let service = try JobsMarketplaceService(entitlements: ledger)
    let draft = jobVacancy(employer)
    try await service.createVacancy(draft, employer: jobEmployer(employer))
    _ = try await service.submit(draft.id, actor: "employer")
    #expect(try await service.moderate(draft.id, actor: "moderator").status == .active)
    #expect(await ledger.available(employerID: employer, kind: .vacancyPublication) == 0)
  }
  @Test func unsafeVacancyRejectedAndEntitlementReleased() async throws {
    let employer = UUID()
    let ledger = try JobsEntitlementLedger()
    try await ledger.credit(
      employerID: employer, kind: .vacancyPublication, quantity: 1, paymentEventID: "payment")
    let service = try JobsMarketplaceService(entitlements: ledger)
    let draft = jobVacancy(employer, text: "Внесок та оплати кандидатом")
    try await service.createVacancy(draft, employer: jobEmployer(employer))
    _ = try await service.submit(draft.id, actor: "employer")
    #expect(try await service.moderate(draft.id, actor: "moderator").status == .rejected)
    #expect(await ledger.available(employerID: employer, kind: .vacancyPublication) == 1)
  }
  @Test func freePrivateCandidateAndImmutableApplicationSnapshot() async throws {
    let employer = UUID()
    let ledger = try JobsEntitlementLedger()
    let service = try JobsMarketplaceService(entitlements: ledger)
    var profile = EmploymentProfile(
      id: UUID(), accountID: UUID(), roles: ["Водій"], locality: "Київ", remoteModes: [.onsite],
      desiredSalary: jobSalary(), employmentTypes: [], schedules: [], experience: nil,
      skills: ["пунктуальність"], languages: ["uk"], licenses: ["B"], workAuthorization: nil,
      availability: nil, visibility: .private, consentedAt: nil, permittedDisplayName: nil,
      restrictedEmail: "private@example.test", restrictedPhone: "+380")
    try await service.upsertProfile(profile)
    let active = jobVacancy(employer, state: .active)
    try await service.ingestATS(eventID: "ats", vacancy: active, capabilities: ["vacancy_sync"])
    let application = try await service.apply(
      vacancyID: active.id, profileID: profile.id, cvID: nil, answers: [:], confirmed: true)
    profile.skills = ["changed"]
    try await service.upsertProfile(profile)
    #expect(application.snapshot.skills == ["пунктуальність"])
  }
  @Test func paidCandidateSearchNeverLeaksRestrictedContact() async throws {
    let employer = UUID()
    let ledger = try JobsEntitlementLedger()
    let service = try JobsMarketplaceService(entitlements: ledger)
    let profile = EmploymentProfile(
      id: UUID(), accountID: UUID(), roles: ["Водій"], locality: nil, remoteModes: [],
      desiredSalary: nil, employmentTypes: [], schedules: [], experience: nil, skills: [],
      languages: [], licenses: [], workAuthorization: nil, availability: nil,
      visibility: .discoverable, consentedAt: .now, permittedDisplayName: "Ім’я",
      restrictedEmail: "secret@example.test", restrictedPhone: "+380")
    try await service.upsertProfile(profile)
    await #expect(throws: JobsError.insufficientEntitlement) {
      try await service.searchCandidates(employerID: employer, query: "водій", eventID: "no-credit")
    }
    try await ledger.credit(
      employerID: employer, kind: .candidateSearch, quantity: 1, paymentEventID: "payment")
    let result = try await service.searchCandidates(
      employerID: employer, query: "водій", eventID: "search")
    #expect(result.first?.restrictedEmail == nil && result.first?.restrictedPhone == nil)
  }
  @Test func ourJobsFirstAndFallbackOnlyWhenInsufficient() async {
    let employer = UUID()
    let selector = JobsSourceSelector()
    let counter = JobCallCounter()
    let first = jobVacancy(employer, state: .active)
    let second = jobVacancy(employer, state: .active)
    let enough = await selector.select(
      jobRequest(), direct: [first, second], commercial: [],
      external: {
        await counter.hit()
        return []
      })
    #expect(await counter.value == 0 && enough.count == 2)
    let external = jobVacancy(employer, tier: .externalFallbackNoVerifiedRevenue, state: .active)
    let mixed = await selector.select(
      jobRequest(), direct: [first], commercial: [],
      external: {
        await counter.hit()
        return [external]
      })
    #expect(await counter.value == 1)
    #expect(mixed.first?.vacancy.sourceTier == .directPaidEmployer)
  }
  @Test func lifecycleValidatedIdempotentAndComplaintNotAutomaticGuilt() async throws {
    let employer = UUID()
    let ledger = try JobsEntitlementLedger()
    let service = try JobsMarketplaceService(entitlements: ledger)
    let profile = EmploymentProfile(
      id: UUID(), accountID: UUID(), roles: ["Водій"], locality: nil, remoteModes: [],
      desiredSalary: nil, employmentTypes: [], schedules: [], experience: nil, skills: [],
      languages: [], licenses: [], workAuthorization: nil, availability: nil, visibility: .private,
      consentedAt: nil, permittedDisplayName: nil, restrictedEmail: nil, restrictedPhone: nil)
    try await service.upsertProfile(profile)
    let active = jobVacancy(employer, state: .active)
    try await service.ingestATS(eventID: "ats", vacancy: active, capabilities: ["vacancy_sync"])
    let app = try await service.apply(
      vacancyID: active.id, profileID: profile.id, cvID: nil, answers: [:], confirmed: true)
    let received = try await service.transition(
      app.id, to: .received, eventID: "received", actor: "ats")
    #expect(
      try await service.transition(app.id, to: .received, eventID: "received", actor: "ats")
        == received)
    await #expect(throws: JobsError.invalidTransition) {
      try await service.transition(app.id, to: .hired, eventID: "bad", actor: "ats")
    }
    #expect(
      try await service.complain(
        vacancyID: active.id, reporterID: profile.accountID, kind: .serviceFeedback, evidence: nil
      ).disposition == .recorded)
    #expect(await service.vacancy(active.id)?.status == .active)
  }
  @Test func watchAndATSDedupSurviveRestart() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      .appendingPathComponent("jobs.json")
    let employer = UUID()
    let ledger = try JobsEntitlementLedger()
    let active = jobVacancy(employer, state: .active)
    let watch = JobWatch(
      id: UUID(), accountID: UUID(), request: jobRequest(), paused: false, seenVacancyIDs: [])
    do {
      let service = try JobsMarketplaceService(entitlements: ledger, persistenceURL: file)
      try await service.ingestATS(eventID: "event", vacancy: active, capabilities: ["vacancy_sync"])
      try await service.ingestATS(eventID: "event", vacancy: active, capabilities: ["vacancy_sync"])
      try await service.saveWatch(watch)
      #expect(await service.watchMatches(watch.id, candidates: [active]).count == 1)
    }
    let restored = try JobsMarketplaceService(entitlements: ledger, persistenceURL: file)
    #expect(await restored.watchMatches(watch.id, candidates: [active]).isEmpty)
  }

  @Test func multipleCVsRequiredCVAndMustHaveScreeningAreEnforced() async throws {
    let employer = UUID()
    let ledger = try JobsEntitlementLedger()
    let service = try JobsMarketplaceService(entitlements: ledger)
    let profile = EmploymentProfile(
      id: UUID(), accountID: UUID(), roles: ["Водій", "Кур’єр"], locality: "Київ",
      remoteModes: [.onsite], desiredSalary: jobSalary(), employmentTypes: ["повна"],
      schedules: ["денна"], experience: "5 років", skills: ["керування"], languages: ["uk"],
      licenses: ["B"], workAuthorization: "explicit", availability: "now", visibility: .private,
      consentedAt: nil, permittedDisplayName: "Кандидат", restrictedEmail: nil, restrictedPhone: nil
    )
    try await service.upsertProfile(profile)
    let cv1 = CandidateCV(
      id: UUID(), profileID: profile.id, version: 1, fileReference: "secure://cv-1",
      mimeType: "application/pdf", createdAt: .now)
    let cv2 = CandidateCV(
      id: UUID(), profileID: profile.id, version: 2, fileReference: "secure://cv-2",
      mimeType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      createdAt: .now)
    try await service.addCV(cv1)
    try await service.addCV(cv2)
    let question = JobScreeningQuestion(id: UUID(), prompt: "Маєте посвідчення B?", kind: .mustHave)
    var active = jobVacancy(employer, state: .active)
    active.cvRequirement = .required
    active.screening = [question]
    try await service.ingestATS(
      eventID: "required-cv", vacancy: active, capabilities: ["vacancy_sync"])
    await #expect(throws: JobsError.cvRequired) {
      try await service.apply(
        vacancyID: active.id, profileID: profile.id, cvID: nil, answers: [question.id: "так"],
        confirmed: true)
    }
    await #expect(throws: JobsError.invalid) {
      try await service.apply(
        vacancyID: active.id, profileID: profile.id, cvID: cv2.id, answers: [:], confirmed: true)
    }
    let app = try await service.apply(
      vacancyID: active.id, profileID: profile.id, cvID: cv2.id, answers: [question.id: "так"],
      confirmed: true)
    #expect(app.snapshot.cvVersion == 2 && app.snapshot.roles.count == 2)
  }

  @Test func materialEditTriggersReviewAndSalarySemanticsFailClosed() async throws {
    let employer = UUID()
    let ledger = try JobsEntitlementLedger()
    let service = try JobsMarketplaceService(entitlements: ledger)
    let active = jobVacancy(employer, state: .active)
    try await service.ingestATS(eventID: "active", vacancy: active, capabilities: ["vacancy_sync"])
    let edited = try await service.edit(
      active.id, details: "Нові обов’язки", salary: jobSalary(), actor: "employer")
    #expect(edited.status == .needsReview && edited.version == 2)
    let invalidSalary = JobSalary(
      minimum: 60_000, maximum: 40_000, currency: "UAH", period: .monthly, basis: .gross,
      guaranteed: nil, variableDescription: "bonus unknown")
    #expect(!invalidSalary.valid)
    await #expect(throws: JobsError.invalid) {
      try await service.edit(active.id, details: "x", salary: invalidSalary, actor: "employer")
    }
  }

  @Test func salaryMismatchNeedsReviewAndCrediblePaymentScamProtectsWithoutPublicGuilt()
    async throws
  {
    let employer = UUID()
    let service = try JobsMarketplaceService(entitlements: JobsEntitlementLedger())
    let active = jobVacancy(employer, state: .active)
    try await service.ingestATS(eventID: "active", vacancy: active, capabilities: ["vacancy_sync"])
    let mismatch = try await service.complain(
      vacancyID: active.id, reporterID: UUID(), kind: .salaryMismatch, evidence: "offer differs")
    #expect(mismatch.disposition == .reviewRequired)
    let scam = try await service.complain(
      vacancyID: active.id, reporterID: UUID(), kind: .paymentRequest,
      evidence: "payment screenshot")
    #expect(scam.disposition == .temporarilySuspended)
    #expect(await service.vacancy(active.id)?.status == .needsReview)
  }

  @Test func invitationRequiresDiscoverabilityPaidEntitlementAndDeclineKeepsContactPrivate()
    async throws
  {
    let employer = UUID()
    let ledger = try JobsEntitlementLedger()
    let service = try JobsMarketplaceService(entitlements: ledger)
    let privateProfile = EmploymentProfile(
      id: UUID(), accountID: UUID(), roles: ["Водій"], locality: nil, remoteModes: [],
      desiredSalary: nil, employmentTypes: [], schedules: [], experience: nil, skills: [],
      languages: [], licenses: [], workAuthorization: nil, availability: nil, visibility: .private,
      consentedAt: nil, permittedDisplayName: nil, restrictedEmail: "hidden@test",
      restrictedPhone: nil)
    try await service.upsertProfile(privateProfile)
    await #expect(throws: JobsError.candidatePrivate) {
      try await service.invite(
        employerID: employer, profileID: privateProfile.id, vacancyID: UUID(), eventID: "private")
    }
    var visible = privateProfile
    visible = .init(
      id: UUID(), accountID: privateProfile.accountID, roles: privateProfile.roles, locality: nil,
      remoteModes: [], desiredSalary: nil, employmentTypes: [], schedules: [], experience: nil,
      skills: [], languages: [], licenses: [], workAuthorization: nil, availability: nil,
      visibility: .discoverable, consentedAt: .now, permittedDisplayName: "Allowed",
      restrictedEmail: "hidden@test", restrictedPhone: nil)
    try await service.upsertProfile(visible)
    try await ledger.credit(
      employerID: employer, kind: .invitation, quantity: 1, paymentEventID: "invite-credit")
    let invitation = try await service.invite(
      employerID: employer, profileID: visible.id, vacancyID: UUID(), eventID: "invite")
    #expect(try await service.respond(invitation.id, accept: false) == nil)
  }

  @Test func ATSRequiresDeclaredCapabilityRejectsStaleAndPropagatesClose() async throws {
    let employer = UUID()
    let service = try JobsMarketplaceService(entitlements: JobsEntitlementLedger())
    let active = jobVacancy(employer, state: .active)
    await #expect(throws: JobsError.unsupportedCapability) {
      try await service.ingestATS(eventID: "bad", vacancy: active, capabilities: [])
    }
    var closed = active
    closed.status = .closed
    closed.updatedAt = active.updatedAt.addingTimeInterval(1)
    try await service.ingestATS(eventID: "create", vacancy: active, capabilities: ["vacancy_sync"])
    try await service.ingestATS(eventID: "close", vacancy: closed, capabilities: ["vacancy_sync"])
    #expect(await service.vacancy(active.id)?.status == .closed)
    var stale = active
    stale.updatedAt = active.updatedAt.addingTimeInterval(-1)
    await #expect(throws: JobsError.staleEvent) {
      try await service.ingestATS(eventID: "stale", vacancy: stale, capabilities: ["vacancy_sync"])
    }
  }

  @Test func expiredVacancyAndHardConstraintsNeverMatch() {
    let employer = UUID()
    let selector = JobsSourceSelector()
    let now = Date()
    var expired = jobVacancy(employer, state: .active)
    expired.expiresAt = now.addingTimeInterval(-1)
    var low = jobVacancy(employer, state: .active)
    low.salary = JobSalary(
      minimum: 10_000, maximum: 20_000, currency: "UAH", period: .monthly, basis: .gross,
      guaranteed: 10_000, variableDescription: nil)
    #expect(selector.matches(jobRequest(), in: [expired, low], now: now).isEmpty)
  }
}
