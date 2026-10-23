import Foundation

enum JobsSourceTier: String, Codable, Sendable {
  case directPaidEmployer, commercialPartner, externalFallbackNoVerifiedRevenue
}
enum VacancyState: String, Codable, Sendable {
  case draft, pendingModeration, active, needsReview, rejected, suspended, closed, expired
}
enum CandidateVisibility: String, Codable, Sendable { case `private`, discoverable }
enum CVRequirement: String, Codable, Sendable { case optional, required }
enum JobCriterionKind: String, Codable, Sendable { case mustHave, preferred, informational }
enum SalaryBasis: String, Codable, Sendable { case gross, net, unknown }
enum SalaryPeriod: String, Codable, Sendable { case hourly, monthly, annual }
enum RemoteMode: String, Codable, Sendable { case onsite, hybrid, remote }
enum JobsEntitlementKind: String, Codable, CaseIterable, Sendable {
  case vacancyPublication, promotion, candidateSearch, invitation, enterpriseConnector
}
enum JobApplicationState: String, Codable, Sendable {
  case submitted, received, viewed, interviewProposed, interviewScheduled, offer, hired, rejected,
    withdrawn, closed, expired, cancelled, failed
}
enum JobComplaintKind: String, Codable, Sendable {
  case serviceFeedback, outdated, misleadingTerms, salaryMismatch, impersonation, paymentRequest,
    phishing, fraud, illegalActivity, harassmentPolicy, reviewRequired
}
enum ComplaintDisposition: String, Codable, Sendable {
  case recorded, reviewRequired, temporarilySuspended, dismissed, resolved, appealed
}
enum JobsError: Error, Equatable, Sendable {
  case invalid, insufficientEntitlement, employerNotVerified, invalidTransition, cvRequired,
    candidatePrivate, consentRequired, inactiveVacancy, unsupportedCapability, staleEvent
}

struct JobSalary: Equatable, Codable, Sendable {
  let minimum: Decimal?, maximum: Decimal?, currency: String, period: SalaryPeriod,
    basis: SalaryBasis, guaranteed: Decimal?, variableDescription: String?
  var valid: Bool {
    currency.count == 3 && [minimum, maximum, guaranteed].compactMap { $0 }.allSatisfy { $0 >= 0 }
      && !(minimum != nil && maximum != nil && minimum! > maximum!)
  }
}
struct JobCriterion: Equatable, Codable, Sendable {
  let value: String
  let kind: JobCriterionKind
}
struct JobScreeningQuestion: Identifiable, Equatable, Codable, Sendable {
  let id: UUID
  let prompt: String
  let kind: JobCriterionKind
}
struct JobsAuditEvent: Equatable, Codable, Sendable {
  let eventID, action, actor, evidence: String
  let occurredAt: Date
}
struct JobVacancy: Identifiable, Equatable, Codable, Sendable {
  let id, employerID: UUID
  let externalID, sourceProviderID: String?
  var role, details: String
  var locality: String?
  var remoteMode: RemoteMode
  var salary: JobSalary?
  var employmentType: String
  var schedule, experience: String?
  var criteria: [JobCriterion]
  var languages, licenses: [String]
  var positions: Int
  var cvRequirement: CVRequirement
  var screening: [JobScreeningQuestion]
  var applicationURL: URL?
  var sourceTier: JobsSourceTier
  var commercialEvidenceID: String?
  var status: VacancyState
  let createdAt: Date
  var updatedAt: Date
  var publishedAt, expiresAt: Date?
  var version: Int
  var moderationReasons: [String]
  var audit: [JobsAuditEvent]
}
struct EmploymentProfile: Identifiable, Equatable, Codable, Sendable {
  let id, accountID: UUID
  var roles: [String]
  var locality: String?
  var remoteModes: Set<RemoteMode>
  var desiredSalary: JobSalary?
  var employmentTypes, schedules: [String]
  var experience: String?
  var skills, languages, licenses: [String]
  var workAuthorization, availability: String?
  var visibility: CandidateVisibility
  var consentedAt: Date?
  var permittedDisplayName, restrictedEmail, restrictedPhone: String?
}
struct CandidateCV: Identifiable, Equatable, Codable, Sendable {
  let id, profileID: UUID
  let version: Int
  let fileReference, mimeType: String
  let createdAt: Date
}
struct JobApplicationSnapshot: Equatable, Codable, Sendable {
  let profileID: UUID
  let roles: [String]
  let locality: String?
  let skills, languages, licenses: [String]
  let cvID: UUID?
  let cvVersion: Int?
  let vacancyID: UUID
  let vacancyVersion: Int
  let screeningAnswers: [UUID: String]
  let consentedAt: Date
  let sourceTier: JobsSourceTier
  let attributionID: String?
}
struct JobApplication: Identifiable, Equatable, Codable, Sendable {
  let id, candidateAccountID, employerID: UUID
  let snapshot: JobApplicationSnapshot
  var state: JobApplicationState
  var events: [JobsAuditEvent]
}
struct EmployerInvitation: Identifiable, Equatable, Codable, Sendable {
  let id, employerID, profileID, vacancyID: UUID
  var accepted: Bool?
  let createdAt: Date
  var respondedAt: Date?
}
struct JobComplaint: Identifiable, Equatable, Codable, Sendable {
  let id, vacancyID, reporterID: UUID
  let kind: JobComplaintKind
  let evidence: String?
  var disposition: ComplaintDisposition
  let createdAt: Date
  var audit: [JobsAuditEvent]
}
struct JobSearchRequest: Equatable, Codable, Sendable {
  var role: String
  var locality: String?
  var remoteModes: Set<RemoteMode>
  var minimumSalary: Decimal?
  var currency, employmentType: String?
  var scheduleExclusions, mustHave, preferred: [String]
  var limit: Int
}
struct JobWatch: Identifiable, Equatable, Codable, Sendable {
  let id, accountID: UUID
  var request: JobSearchRequest
  var paused: Bool
  var seenVacancyIDs: Set<UUID>
}
struct JobMatch: Equatable, Sendable {
  let vacancy: JobVacancy
  let score: Int
}
struct JobSourceDescriptor: Equatable, Codable, Sendable {
  let providerID, displayName: String
  let tier: JobsSourceTier
  let officialMechanism: String
  let requiresCredential: Bool
  let commercialEvidenceID: String?
  let effectiveUntil: Date?
  let observedAt: Date
  let actionBaseURL: URL
  let capabilities: Set<String>
}

private struct EntitlementSnapshot: Codable {
  var balances: [String: Int] = [:], reservations: [String: String] = [:]
  var processed: Set<String> = []
}
actor JobsEntitlementLedger {
  private var state: EntitlementSnapshot
  private let file: URL?
  init(persistenceURL: URL? = nil) throws {
    file = persistenceURL
    if let persistenceURL, let d = try? Data(contentsOf: persistenceURL) {
      state = try JSONDecoder().decode(EntitlementSnapshot.self, from: d)
    } else {
      state = .init()
    }
  }
  private func key(_ id: UUID, _ kind: JobsEntitlementKind) -> String { "\(id):\(kind.rawValue)" }
  func credit(employerID: UUID, kind: JobsEntitlementKind, quantity: Int, paymentEventID: String)
    throws
  {
    guard quantity > 0, !paymentEventID.isEmpty else { throw JobsError.invalid }
    if state.processed.contains(paymentEventID) { return }
    state.balances[key(employerID, kind), default: 0] += quantity
    state.processed.insert(paymentEventID)
    try save()
  }
  func reserve(employerID: UUID, kind: JobsEntitlementKind, operationID: String) throws {
    guard !operationID.isEmpty else { throw JobsError.invalid }
    if state.reservations[operationID] != nil { return }
    let k = key(employerID, kind)
    guard state.balances[k, default: 0] > 0 else { throw JobsError.insufficientEntitlement }
    state.balances[k, default: 0] -= 1
    state.reservations[operationID] = k
    try save()
  }
  func consume(operationID: String, eventID: String) throws {
    guard !eventID.isEmpty else { throw JobsError.invalid }
    if state.processed.contains(eventID) { return }
    guard state.reservations.removeValue(forKey: operationID) != nil else {
      throw JobsError.invalid
    }
    state.processed.insert(eventID)
    try save()
  }
  func release(operationID: String, eventID: String) throws {
    guard !eventID.isEmpty else { throw JobsError.invalid }
    if state.processed.contains(eventID) { return }
    guard let k = state.reservations.removeValue(forKey: operationID) else {
      throw JobsError.invalid
    }
    state.balances[k, default: 0] += 1
    state.processed.insert(eventID)
    try save()
  }
  func available(employerID: UUID, kind: JobsEntitlementKind) -> Int {
    state.balances[key(employerID, kind), default: 0]
  }
  private func save() throws {
    guard let file else { return }
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(state).write(to: file, options: .atomic)
  }
}

struct JobsSourceSelector: Sendable {
  func matches(_ request: JobSearchRequest, in values: [JobVacancy], now: Date) -> [JobMatch] {
    values.compactMap { vacancy -> JobMatch? in
      let notExpired = vacancy.expiresAt.map { $0 > now } ?? true
      let localityMatches =
        request.locality.map { locality in
          vacancy.locality?.localizedCaseInsensitiveContains(locality) == true
            || vacancy.remoteMode == .remote
        } ?? true
      let salaryMatches =
        request.minimumSalary.map { minimum in
          vacancy.salary?.maximum.map { $0 >= minimum } ?? false
        } ?? true
      let currencyMatches = request.currency.map { vacancy.salary?.currency == $0 } ?? true
      let employmentMatches =
        request.employmentType.map {
          vacancy.employmentType.localizedCaseInsensitiveContains($0)
        } ?? true
      let scheduleMatches = request.scheduleExclusions.allSatisfy {
        !(vacancy.schedule ?? "").localizedCaseInsensitiveContains($0)
      }
      let mustHaveMatches = request.mustHave.allSatisfy { need in
        vacancy.criteria.contains { criterion in
          criterion.kind == .mustHave && criterion.value.localizedCaseInsensitiveContains(need)
        }
      }
      guard vacancy.status == .active, notExpired,
        vacancy.role.localizedCaseInsensitiveContains(request.role), localityMatches,
        request.remoteModes.isEmpty || request.remoteModes.contains(vacancy.remoteMode),
        salaryMatches, currencyMatches, employmentMatches, scheduleMatches, mustHaveMatches
      else { return nil }
      let tier =
        vacancy.sourceTier == .directPaidEmployer
        ? 20 : vacancy.sourceTier == .commercialPartner ? 10 : 0
      let preferred = request.preferred.filter { wanted in
        vacancy.criteria.contains {
          $0.kind == .preferred && $0.value.localizedCaseInsensitiveContains(wanted)
        }
      }.count
      return JobMatch(vacancy: vacancy, score: 100 + tier + preferred * 5)
    }.sorted {
      $0.score == $1.score ? $0.vacancy.updatedAt > $1.vacancy.updatedAt : $0.score > $1.score
    }
  }
  func select(
    _ request: JobSearchRequest, direct: [JobVacancy], commercial: [JobVacancy],
    external: @Sendable () async -> [JobVacancy], now: Date = .now
  ) async -> [JobMatch] {
    let own = matches(request, in: direct.filter { $0.sourceTier == .directPaidEmployer }, now: now)
    let revenue = matches(
      request,
      in: commercial.filter {
        $0.sourceTier == .commercialPartner && $0.commercialEvidenceID != nil
      }, now: now)
    let preferred = own + revenue
    let threshold = min(max(request.limit, 1), 3)
    if preferred.count >= threshold { return Array(preferred.prefix(request.limit)) }
    let fallback = matches(request, in: await external(), now: now).filter {
      $0.vacancy.sourceTier == .externalFallbackNoVerifiedRevenue
    }
    return Array((preferred + fallback).sorted { $0.score > $1.score }.prefix(request.limit))
  }
}

private struct JobsSnapshot: Codable {
  var vacancies: [JobVacancy] = [], profiles: [EmploymentProfile] = [], cvs: [CandidateCV] = [],
    applications: [JobApplication] = [], invitations: [EmployerInvitation] = [],
    complaints: [JobComplaint] = [], watches: [JobWatch] = []
  var processed: Set<String> = []
}
actor JobsMarketplaceService {
  private var state: JobsSnapshot
  private let file: URL?
  private let credits: JobsEntitlementLedger
  private let inbox: BusinessOperationsStore?
  init(
    entitlements: JobsEntitlementLedger, persistenceURL: URL? = nil,
    inbox: BusinessOperationsStore? = nil
  ) throws {
    credits = entitlements
    file = persistenceURL
    self.inbox = inbox
    if let persistenceURL, let d = try? Data(contentsOf: persistenceURL) {
      state = try JSONDecoder().decode(JobsSnapshot.self, from: d)
    } else {
      state = .init()
    }
  }
  func upsertProfile(_ p: EmploymentProfile) throws {
    guard !p.roles.isEmpty, p.desiredSalary?.valid ?? true,
      p.visibility == .private || p.consentedAt != nil
    else { throw JobsError.consentRequired }
    state.profiles.removeAll { $0.id == p.id }
    state.profiles.append(p)
    try save()
  }
  func addCV(_ cv: CandidateCV) throws {
    guard state.profiles.contains(where: { $0.id == cv.profileID }),
      [
        "application/pdf",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      ].contains(cv.mimeType), !cv.fileReference.isEmpty
    else { throw JobsError.invalid }
    state.cvs.removeAll { $0.id == cv.id }
    state.cvs.append(cv)
    try save()
  }
  func createVacancy(_ v: JobVacancy, employer: PartnerOnboardingRecord) throws {
    guard employer.partnerID == v.employerID, employer.state == .active, !v.role.isEmpty,
      !v.details.isEmpty, v.positions > 0, v.salary?.valid ?? true, v.status == .draft
    else { throw JobsError.employerNotVerified }
    state.vacancies.append(v)
    try save()
  }
  func submit(_ id: UUID, actor: String, now: Date = .now) async throws -> JobVacancy {
    let i = try idx(id)
    guard state.vacancies[i].status == .draft else { throw JobsError.invalidTransition }
    try await credits.reserve(
      employerID: state.vacancies[i].employerID, kind: .vacancyPublication,
      operationID: "publish:\(id)")
    state.vacancies[i].status = .pendingModeration
    state.vacancies[i].updatedAt = now
    state.vacancies[i].audit.append(event("submit", actor, "reserved", now))
    try save()
    return state.vacancies[i]
  }
  func moderate(_ id: UUID, actor: String, now: Date = .now) async throws -> JobVacancy {
    let i = try idx(id)
    guard state.vacancies[i].status == .pendingModeration else { throw JobsError.invalidTransition }
    let reasons = risk(state.vacancies[i])
    state.vacancies[i].moderationReasons = reasons
    state.vacancies[i].status =
      reasons.isEmpty
      ? .active
      : (reasons.contains("candidate_payment") || reasons.contains("phishing")
        ? .rejected : .needsReview)
    state.vacancies[i].updatedAt = now
    if state.vacancies[i].status == .active {
      state.vacancies[i].publishedAt = now
      try await credits.consume(operationID: "publish:\(id)", eventID: "delivered:\(id)")
    } else if state.vacancies[i].status == .rejected {
      try await credits.release(operationID: "publish:\(id)", eventID: "rejected:\(id)")
    }
    state.vacancies[i].audit.append(event("moderate", actor, reasons.joined(separator: ","), now))
    try save()
    return state.vacancies[i]
  }
  func edit(_ id: UUID, details: String, salary: JobSalary?, actor: String, now: Date = .now) throws
    -> JobVacancy
  {
    let i = try idx(id)
    guard !details.isEmpty, salary?.valid ?? true else { throw JobsError.invalid }
    let material = state.vacancies[i].details != details || state.vacancies[i].salary != salary
    state.vacancies[i].details = details
    state.vacancies[i].salary = salary
    state.vacancies[i].version += 1
    state.vacancies[i].updatedAt = now
    if material && state.vacancies[i].status == .active { state.vacancies[i].status = .needsReview }
    state.vacancies[i].audit.append(
      event("edit", actor, material ? "material_review" : "minor", now))
    try save()
    return state.vacancies[i]
  }
  func apply(
    vacancyID: UUID, profileID: UUID, cvID: UUID?, answers: [UUID: String], confirmed: Bool,
    at: Date = .now, attributionID: String? = nil
  ) async throws -> JobApplication {
    guard confirmed else { throw JobsError.consentRequired }
    let v = state.vacancies[try idx(vacancyID)]
    guard v.status == .active else { throw JobsError.inactiveVacancy }
    guard let p = state.profiles.first(where: { $0.id == profileID }) else {
      throw JobsError.invalid
    }
    let cv = cvID.flatMap { id in state.cvs.first { $0.id == id && $0.profileID == profileID } }
    if v.cvRequirement == .required && cv == nil { throw JobsError.cvRequired }
    guard
      Set(v.screening.filter { $0.kind == .mustHave }.map { $0.id }).isSubset(of: Set(answers.keys))
    else { throw JobsError.invalid }
    let snapshot = JobApplicationSnapshot(
      profileID: p.id, roles: p.roles, locality: p.locality, skills: p.skills,
      languages: p.languages, licenses: p.licenses, cvID: cv?.id, cvVersion: cv?.version,
      vacancyID: v.id, vacancyVersion: v.version, screeningAnswers: answers, consentedAt: at,
      sourceTier: v.sourceTier, attributionID: attributionID)
    let a = JobApplication(
      id: UUID(), candidateAccountID: p.accountID, employerID: v.employerID, snapshot: snapshot,
      state: .submitted, events: [event("apply", p.accountID.uuidString, "confirmed_snapshot", at)])
    state.applications.append(a)
    try save()
    if let inbox {
      let customer = try await inbox.upsertCustomer(
        partnerID: v.employerID, externalReference: p.accountID.uuidString,
        displayName: p.permittedDisplayName, permittedEmail: nil, permittedPhone: nil, at: at)
      _ = try await inbox.ingestInteraction(
        .init(
          id: UUID(), partnerID: v.employerID, eventID: "jobs:\(a.id)", source: .universalAssistant,
          sourceReference: a.id.uuidString, customerID: customer.id, occurredAt: at,
          inquiryReference: v.id.uuidString, category: "job_application", relatedTransactionID: nil,
          status: .open, assigneeReference: nil))
    }
    return a
  }
  func transition(
    _ id: UUID, to next: JobApplicationState, eventID: String, actor: String, at: Date = .now
  ) throws -> JobApplication {
    guard let i = state.applications.firstIndex(where: { $0.id == id }) else {
      throw JobsError.invalid
    }
    if state.processed.contains(eventID) { return state.applications[i] }
    guard allowed(state.applications[i].state, next) else { throw JobsError.invalidTransition }
    state.applications[i].state = next
    state.applications[i].events.append(event(eventID, actor, next.rawValue, at))
    state.processed.insert(eventID)
    try save()
    return state.applications[i]
  }
  func searchCandidates(employerID: UUID, query: String, eventID: String) async throws
    -> [EmploymentProfile]
  {
    try await credits.reserve(employerID: employerID, kind: .candidateSearch, operationID: eventID)
    try await credits.consume(operationID: eventID, eventID: "consume:\(eventID)")
    return state.profiles.filter {
      $0.visibility == .discoverable && $0.consentedAt != nil
        && $0.roles.contains { role in role.localizedCaseInsensitiveContains(query) }
    }.map {
      var x = $0
      x.restrictedEmail = nil
      x.restrictedPhone = nil
      return x
    }
  }
  func invite(employerID: UUID, profileID: UUID, vacancyID: UUID, eventID: String, at: Date = .now)
    async throws -> EmployerInvitation
  {
    guard let p = state.profiles.first(where: { $0.id == profileID }),
      p.visibility == .discoverable, p.consentedAt != nil
    else { throw JobsError.candidatePrivate }
    try await credits.reserve(employerID: employerID, kind: .invitation, operationID: eventID)
    try await credits.consume(operationID: eventID, eventID: "consume:\(eventID)")
    let x = EmployerInvitation(
      id: UUID(), employerID: employerID, profileID: profileID, vacancyID: vacancyID, accepted: nil,
      createdAt: at, respondedAt: nil)
    state.invitations.append(x)
    try save()
    return x
  }
  func respond(_ id: UUID, accept: Bool, at: Date = .now) throws -> EmploymentProfile? {
    guard let i = state.invitations.firstIndex(where: { $0.id == id }) else {
      throw JobsError.invalid
    }
    state.invitations[i].accepted = accept
    state.invitations[i].respondedAt = at
    try save()
    guard accept else { return nil }
    return state.profiles.first { $0.id == state.invitations[i].profileID }
  }
  func complain(
    vacancyID: UUID, reporterID: UUID, kind: JobComplaintKind, evidence: String?, at: Date = .now
  ) throws -> JobComplaint {
    let high: [JobComplaintKind] = [
      .paymentRequest, .phishing, .fraud, .impersonation, .illegalActivity,
    ]
    let disposition: ComplaintDisposition =
      high.contains(kind) && !(evidence ?? "").isEmpty
      ? .temporarilySuspended
      : ([.salaryMismatch, .misleadingTerms, .reviewRequired].contains(kind)
        ? .reviewRequired : .recorded)
    let c = JobComplaint(
      id: UUID(), vacancyID: vacancyID, reporterID: reporterID, kind: kind, evidence: evidence,
      disposition: disposition, createdAt: at,
      audit: [event("complaint", reporterID.uuidString, disposition.rawValue, at)])
    if disposition == .temporarilySuspended,
      let i = state.vacancies.firstIndex(where: { $0.id == vacancyID })
    {
      state.vacancies[i].status = .needsReview
    }
    state.complaints.append(c)
    try save()
    return c
  }
  func ingestATS(eventID: String, vacancy: JobVacancy, capabilities: Set<String>, now: Date = .now)
    throws
  {
    guard capabilities.contains("vacancy_sync") else { throw JobsError.unsupportedCapability }
    if state.processed.contains(eventID) { return }
    guard vacancy.updatedAt <= now.addingTimeInterval(300) else { throw JobsError.staleEvent }
    if let i = state.vacancies.firstIndex(where: {
      $0.sourceProviderID == vacancy.sourceProviderID && $0.externalID == vacancy.externalID
    }) {
      guard vacancy.updatedAt >= state.vacancies[i].updatedAt else { throw JobsError.staleEvent }
      state.vacancies[i] = vacancy
    } else {
      state.vacancies.append(vacancy)
    }
    state.processed.insert(eventID)
    try save()
  }
  func saveWatch(_ w: JobWatch) throws {
    guard !w.request.role.isEmpty else { throw JobsError.invalid }
    state.watches.removeAll { $0.id == w.id }
    state.watches.append(w)
    try save()
  }
  func watchMatches(_ id: UUID, candidates: [JobVacancy], now: Date = .now) -> [JobVacancy] {
    guard let i = state.watches.firstIndex(where: { $0.id == id }), !state.watches[i].paused else {
      return []
    }
    let found = JobsSourceSelector().matches(state.watches[i].request, in: candidates, now: now).map
    { $0.vacancy }.filter { !state.watches[i].seenVacancyIDs.contains($0.id) }
    state.watches[i].seenVacancyIDs.formUnion(found.map { $0.id })
    try? save()
    return found
  }
  func vacancy(_ id: UUID) -> JobVacancy? { state.vacancies.first { $0.id == id } }
  func application(_ id: UUID) -> JobApplication? { state.applications.first { $0.id == id } }

  /// Publicly visible vacancies: moderated and not expired. Paid-employer
  /// inventory is exposed first; commercial partners only with an evidence id.
  func visibleVacancies(now: Date = .now) -> [JobVacancy] {
    state.vacancies.filter { vacancy in
      guard vacancy.status == .active else { return false }
      guard vacancy.expiresAt.map({ $0 > now }) ?? true else { return false }
      if vacancy.sourceTier == .commercialPartner { return vacancy.commercialEvidenceID != nil }
      return vacancy.sourceTier == .directPaidEmployer
    }
  }

  /// Deterministic search over locally held vacancies. OUR JOBS FIRST, then
  /// evidenced commercial partners; no invented external inventory.
  func search(_ request: JobSearchRequest, now: Date = .now) -> [JobMatch] {
    let visible = visibleVacancies(now: now)
    let matches = JobsSourceSelector().matches(request, in: visible, now: now)
    let limit = max(1, min(request.limit, 50))
    return Array(
      matches.sorted {
        $0.score == $1.score ? $0.vacancy.updatedAt > $1.vacancy.updatedAt : $0.score > $1.score
      }.prefix(limit))
  }

  func counts(now: Date = .now) -> (visible: Int, total: Int) {
    (visibleVacancies(now: now).count, state.vacancies.count)
  }

  private func idx(_ id: UUID) throws -> Int {
    guard let i = state.vacancies.firstIndex(where: { $0.id == id }) else {
      throw JobsError.invalid
    }
    return i
  }
  private func event(_ id: String, _ actor: String, _ evidence: String, _ date: Date)
    -> JobsAuditEvent
  { .init(eventID: id, action: id, actor: actor, evidence: evidence, occurredAt: date) }
  private func risk(_ v: JobVacancy) -> [String] {
    let t = (v.role + " " + v.details).lowercased()
    var r: [String] = []
    if t.contains("внесок") || t.contains("оплати кандидатом") { r.append("candidate_payment") }
    if t.contains("надішли пароль") { r.append("phishing") }
    if t.contains("безкоштовна праця") { r.append("misleading_terms") }
    return r
  }
  private func allowed(_ a: JobApplicationState, _ b: JobApplicationState) -> Bool {
    switch (a, b) {
    case (.submitted, .received), (.submitted, .withdrawn), (.submitted, .failed),
      (.received, .viewed), (.received, .rejected), (.received, .withdrawn),
      (.viewed, .interviewProposed), (.viewed, .rejected),
      (.interviewProposed, .interviewScheduled), (.interviewProposed, .cancelled),
      (.interviewScheduled, .offer), (.interviewScheduled, .rejected),
      (.interviewScheduled, .cancelled), (.offer, .hired), (.offer, .rejected),
      (.offer, .withdrawn):
      true
    default: false
    }
  }
  private func save() throws {
    guard let file else { return }
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(state).write(to: file, options: .atomic)
  }
}
