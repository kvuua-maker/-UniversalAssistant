import Foundation
import Vapor

// MARK: - Transport types
//
// The jobs domain models live in JobsMarketplace.swift and are intentionally
// free of Vapor types. Everything below is the HTTP boundary only: it maps the
// canonical models onto request/response payloads and never re-implements
// business rules.

extension JobSearchRequest: Content {}

struct JobVacancyDTO: Content {
    let id: UUID
    let employerID: UUID
    let role: String
    let details: String
    let locality: String?
    let remoteMode: String
    let salaryMinimum: String?
    let salaryMaximum: String?
    let salaryCurrency: String?
    let salaryPeriod: String?
    let employmentType: String
    let status: String
    let sourceTier: String
    let cvRequirement: String
    let publishedAt: Date?
    let expiresAt: Date?
    let applicationURL: String?
    let score: Int

    init(vacancy: JobVacancy, score: Int) {
        self.id = vacancy.id
        self.employerID = vacancy.employerID
        self.role = vacancy.role
        self.details = vacancy.details
        self.locality = vacancy.locality
        self.remoteMode = vacancy.remoteMode.rawValue
        self.salaryMinimum = vacancy.salary?.minimum.map { "\($0)" }
        self.salaryMaximum = vacancy.salary?.maximum.map { "\($0)" }
        self.salaryCurrency = vacancy.salary?.currency
        self.salaryPeriod = vacancy.salary?.period.rawValue
        self.employmentType = vacancy.employmentType
        self.status = vacancy.status.rawValue
        self.sourceTier = vacancy.sourceTier.rawValue
        self.cvRequirement = vacancy.cvRequirement.rawValue
        self.publishedAt = vacancy.publishedAt
        self.expiresAt = vacancy.expiresAt
        self.applicationURL = vacancy.applicationURL?.absoluteString
        self.score = score
    }
}

struct JobsSearchResponse: Content {
    let matches: [JobVacancyDTO]
    let total: Int
    /// Mirrors JOBS-007..009: our own paid inventory is searched first and
    /// external sources are never invented locally.
    let sourcePolicy: String
    let freshness: Date
}

struct JobsHealthResponse: Content {
    let status: String
    let visibleVacancies: Int
    let totalVacancies: Int
    let sourcePolicy: String
}

private func httpStatus(for error: JobsError) -> HTTPStatus {
    switch error {
    case .insufficientEntitlement: return .paymentRequired
    case .employerNotVerified, .candidatePrivate, .consentRequired: return .forbidden
    case .invalidTransition, .staleEvent, .inactiveVacancy: return .conflict
    case .unsupportedCapability: return .notImplemented
    case .invalid, .cvRequired: return .badRequest
    }
}

// MARK: - Wiring

extension Application {
    /// Mounts the Jobs marketplace HTTP surface.
    ///
    /// Before this existed the entire Jobs domain (`JobsMarketplaceService`,
    /// `JobsEntitlementLedger`, moderation, applications, ATS ingest) was
    /// compiled into the server binary but never constructed by any reachable
    /// `configure*` function, so no client could ever reach it.
    func configureJobsRoutes(storageRoot: URL) throws {
        let directory = storageRoot.appendingPathComponent("jobs", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let entitlements = try JobsEntitlementLedger(
            persistenceURL: directory.appendingPathComponent("entitlements.json"))
        let marketplace = try JobsMarketplaceService(
            entitlements: entitlements,
            persistenceURL: directory.appendingPathComponent("vacancies.json"))

        get("v1", "jobs", "health") { _ async throws -> JobsHealthResponse in
            let counts = await marketplace.counts()
            return JobsHealthResponse(
                status: "healthy",
                visibleVacancies: counts.visible,
                totalVacancies: counts.total,
                sourcePolicy: "our_jobs_first")
        }

        post("v1", "jobs", "search") { request async throws -> JobsSearchResponse in
            let body: JobSearchRequest
            do {
                body = try request.content.decode(JobSearchRequest.self)
            } catch {
                throw Abort(.badRequest, reason: "invalid_jobs_search_request")
            }
            let matches = await marketplace.search(body)
            return JobsSearchResponse(
                matches: matches.map { JobVacancyDTO(vacancy: $0.vacancy, score: $0.score) },
                total: matches.count,
                sourcePolicy: "our_jobs_first",
                freshness: Date())
        }

        get("v1", "jobs", "vacancies", ":vacancyID") { request async throws -> JobVacancyDTO in
            guard let raw = request.parameters.get("vacancyID"), let id = UUID(uuidString: raw) else {
                throw Abort(.badRequest, reason: "invalid_vacancy_id")
            }
            guard let vacancy = await marketplace.vacancy(id),
                vacancy.status == .active,
                vacancy.expiresAt.map({ $0 > Date() }) ?? true
            else {
                throw Abort(.notFound, reason: "vacancy_unavailable")
            }
            return JobVacancyDTO(vacancy: vacancy, score: 0)
        }

        post("v1", "jobs", "applications", ":applicationID", "withdraw") {
            request async throws -> JobVacancyDTO in
            guard let raw = request.parameters.get("applicationID"),
                let id = UUID(uuidString: raw)
            else { throw Abort(.badRequest, reason: "invalid_application_id") }
            guard let application = await marketplace.application(id) else {
                throw Abort(.notFound, reason: "application_not_found")
            }
            do {
                _ = try await marketplace.transition(
                    id, to: .withdrawn, eventID: "withdraw-\(id.uuidString.lowercased())",
                    actor: "candidate", at: Date())
            } catch let error as JobsError {
                throw Abort(httpStatus(for: error), reason: "\(error)")
            }
            guard let vacancy = await marketplace.vacancy(application.snapshot.vacancyID) else {
                throw Abort(.notFound, reason: "vacancy_unavailable")
            }
            return JobVacancyDTO(vacancy: vacancy, score: 0)
        }
    }
}
