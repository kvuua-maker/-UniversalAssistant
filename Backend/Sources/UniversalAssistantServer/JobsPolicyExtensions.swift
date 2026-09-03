import Foundation

enum JobsEnforcementState: String, Codable, Sendable {
  case warning, review, restricted, suspended, terminated, restored
}
struct JobsEnforcement: Identifiable, Equatable, Codable, Sendable {
  let id, employerID: UUID
  let state: JobsEnforcementState
  let reasonCode, actor: String
  let evidenceReferences: [String]
  let occurredAt: Date
  var appealID: UUID?
}
enum JobsAppealState: String, Codable, Sendable { case submitted, underReview, upheld, reversed }
struct JobsAppeal: Identifiable, Equatable, Codable, Sendable {
  let id, enforcementID, employerID: UUID
  let reason, actor: String
  let createdAt: Date
  var state: JobsAppealState
  var resolution: String?
}
struct JobsInterviewProposal: Identifiable, Equatable, Codable, Sendable {
  let id, applicationID: UUID
  let proposedAt: Date
  let locationName: String?
  let onlineURL: URL?
  var candidateAccepted: Bool?
  var calendarEventReference: String?
}
struct SavedJob: Identifiable, Equatable, Codable, Sendable {
  let id, accountID, vacancyID: UUID
  let savedAt: Date
  var lastKnownState: VacancyState
  var lastKnownVersion: Int
}
struct JobsAggregateMetrics: Equatable, Sendable {
  let activeVacancies, discoverableCandidates, applications, invitations, interviews: Int
  let observedAt: Date
}
struct JobsRetentionPolicy: Equatable, Sendable {
  let profileDays, applicationDays, cvDays, billingAuditDays, fraudEvidenceDays: Int
  func retentionDays(for kind: String) -> Int? {
    switch kind {
    case "profile": profileDays
    case "application": applicationDays
    case "cv": cvDays
    case "billing": billingAuditDays
    case "fraud": fraudEvidenceDays
    default: nil
    }
  }
}
struct JobsRuntimeConfiguration: Equatable, Codable, Sendable {
  var publicationPriceMinorUnits: Int
  var promotionPriceMinorUnits: Int
  var candidateSearchQuota, invitationQuota, pageSize: Int
  func validated() throws -> Self {
    guard publicationPriceMinorUnits >= 0, promotionPriceMinorUnits >= 0,
      candidateSearchQuota > 0, invitationQuota > 0, (1...100).contains(pageSize)
    else { throw JobsError.invalid }
    return self
  }
}
struct JobsCommercialSource: Identifiable, Equatable, Codable, Sendable {
  let id, displayName, commercialModel, evidenceReference: String
  let effectiveAt, expiresAt: Date
  let territories, capabilities: Set<String>
  let actionURL: URL
  var suspended: Bool
  func isEligible(at date: Date, territory: String, capability: String) -> Bool {
    !suspended && effectiveAt <= date && expiresAt > date && territories.contains(territory)
      && capabilities.contains(capability) && !evidenceReference.isEmpty
  }
}
struct JobsPromotion: Identifiable, Equatable, Codable, Sendable {
  let id, vacancyID, employerID: UUID
  let entitlementOperationID: String
  let startsAt, endsAt: Date
  var stoppedAt: Date?
  func isActive(vacancy: JobVacancy, at date: Date) -> Bool {
    stoppedAt == nil && vacancy.status == .active && startsAt <= date && endsAt > date
  }
}
enum JobsPolicyError: Error, Equatable {
  case invalidEvidence, blockedEmployer, candidateConfirmationRequired, invalidURL
}

actor JobsPolicyStore {
  private struct Snapshot: Codable {
    var blocks: [String: Date] = [:]
    var saved: [SavedJob] = []
    var enforcement: [JobsEnforcement] = []
    var appeals: [JobsAppeal] = []
    var interviews: [JobsInterviewProposal] = []
  }
  private var state: Snapshot
  private let file: URL?
  init(persistenceURL: URL? = nil) throws {
    file = persistenceURL
    if let persistenceURL, let data = try? Data(contentsOf: persistenceURL) {
      state = try JSONDecoder().decode(Snapshot.self, from: data)
    } else {
      state = .init()
    }
  }
  func block(candidateID: UUID, employerID: UUID, at: Date = .now) throws {
    state.blocks[key(candidateID, employerID)] = at
    try save()
  }
  func mayContact(candidateID: UUID, employerID: UUID) -> Bool {
    state.blocks[key(candidateID, employerID)] == nil
  }
  func saveJob(accountID: UUID, vacancy: JobVacancy, at: Date = .now) throws -> SavedJob {
    if let existing = state.saved.first(where: {
      $0.accountID == accountID && $0.vacancyID == vacancy.id
    }) {
      return existing
    }
    let value = SavedJob(
      id: UUID(), accountID: accountID, vacancyID: vacancy.id, savedAt: at,
      lastKnownState: vacancy.status, lastKnownVersion: vacancy.version)
    state.saved.append(value)
    try save()
    return value
  }
  func refreshSaved(vacancy: JobVacancy) throws {
    for index in state.saved.indices where state.saved[index].vacancyID == vacancy.id {
      state.saved[index].lastKnownState = vacancy.status
      state.saved[index].lastKnownVersion = vacancy.version
    }
    try save()
  }
  func savedJobs(accountID: UUID) -> [SavedJob] { state.saved.filter { $0.accountID == accountID } }
  func enforce(
    employerID: UUID, state newState: JobsEnforcementState, reason: String, actor: String,
    evidence: [String], at: Date = .now
  ) throws -> JobsEnforcement {
    guard !reason.isEmpty, !actor.isEmpty, newState == .warning || !evidence.isEmpty else {
      throw JobsPolicyError.invalidEvidence
    }
    let value = JobsEnforcement(
      id: UUID(), employerID: employerID, state: newState, reasonCode: reason, actor: actor,
      evidenceReferences: evidence, occurredAt: at, appealID: nil)
    state.enforcement.append(value)
    try save()
    return value
  }
  func appeal(enforcementID: UUID, employerID: UUID, reason: String, actor: String, at: Date = .now)
    throws -> JobsAppeal
  {
    guard
      state.enforcement.contains(where: { $0.id == enforcementID && $0.employerID == employerID }),
      !reason.isEmpty
    else { throw JobsPolicyError.invalidEvidence }
    let appeal = JobsAppeal(
      id: UUID(), enforcementID: enforcementID, employerID: employerID, reason: reason,
      actor: actor, createdAt: at, state: .submitted, resolution: nil)
    state.appeals.append(appeal)
    if let index = state.enforcement.firstIndex(where: { $0.id == enforcementID }) {
      state.enforcement[index].appealID = appeal.id
    }
    try save()
    return appeal
  }
  func proposeInterview(
    applicationID: UUID, proposedAt: Date, locationName: String?, onlineURL: URL?
  ) throws -> JobsInterviewProposal {
    if let onlineURL, onlineURL.scheme?.lowercased() != "https" { throw JobsPolicyError.invalidURL }
    let proposal = JobsInterviewProposal(
      id: UUID(), applicationID: applicationID, proposedAt: proposedAt, locationName: locationName,
      onlineURL: onlineURL, candidateAccepted: nil, calendarEventReference: nil)
    state.interviews.append(proposal)
    try save()
    return proposal
  }
  func confirmInterview(_ id: UUID, candidateConfirmed: Bool, calendarEventReference: String?)
    throws -> JobsInterviewProposal
  {
    guard candidateConfirmed else { throw JobsPolicyError.candidateConfirmationRequired }
    guard let index = state.interviews.firstIndex(where: { $0.id == id }) else {
      throw JobsError.invalid
    }
    state.interviews[index].candidateAccepted = true
    state.interviews[index].calendarEventReference = calendarEventReference
    try save()
    return state.interviews[index]
  }
  private func key(_ candidate: UUID, _ employer: UUID) -> String { "\(candidate):\(employer)" }
  private func save() throws {
    guard let file else { return }
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(state).write(to: file, options: .atomic)
  }
}
