import Foundation

enum PartnerPlatformRole: String, Codable, Sendable { case partnerViewer, partnerOperator, internalAdmin }
enum PartnerPlatformPermission: String, Codable, Hashable, Sendable {
    case viewDashboard, manageIntegration, reviewPartners, manageFinance
}

struct PartnerPrincipal: Equatable, Sendable {
    let subjectID: String
    let tenantPartnerID: UUID?
    let role: PartnerPlatformRole
    let permissions: Set<PartnerPlatformPermission>
}

struct PartnerDashboardRecord: Equatable, Codable, Sendable {
    let partnerID: UUID
    let profileStatus: PartnerOnboardingState
    let integrationHealth: String
    let attributedConversions: Int
    let commissionBalance: LedgerMoney
}

struct TenantAccessAuditEvent: Equatable, Sendable {
    let sequence: Int
    let subjectID: String
    let targetPartnerID: UUID
    let operation: String
    let outcome: String
    let occurredAt: Date
}

enum PartnerTenantAccessError: Error, Equatable, Sendable { case unauthenticated, forbidden, invalidRecord }

actor PartnerTenantDataStore {
    private var dashboardRecords: [UUID: PartnerDashboardRecord] = [:]
    private var audit: [TenantAccessAuditEvent] = []

    func upsert(_ record: PartnerDashboardRecord, principal: PartnerPrincipal, at: Date = .now) throws {
        guard !principal.subjectID.isEmpty else { throw PartnerTenantAccessError.unauthenticated }
        guard record.commissionBalance.amount >= 0, record.commissionBalance.currencyCode.count == 3 else {
            throw PartnerTenantAccessError.invalidRecord
        }
        let allowed = principal.role == .internalAdmin
            ? principal.permissions.contains(.reviewPartners)
            : principal.role == .partnerOperator && principal.tenantPartnerID == record.partnerID && principal.permissions.contains(.manageIntegration)
        guard allowed else {
            appendAudit(principal, target: record.partnerID, operation: "dashboard_upsert", outcome: "denied", at: at)
            throw PartnerTenantAccessError.forbidden
        }
        dashboardRecords[record.partnerID] = record
        appendAudit(principal, target: record.partnerID, operation: "dashboard_upsert", outcome: "allowed", at: at)
    }

    func dashboard(for partnerID: UUID, principal: PartnerPrincipal, at: Date = .now) throws -> PartnerDashboardRecord? {
        guard !principal.subjectID.isEmpty else { throw PartnerTenantAccessError.unauthenticated }
        let partnerAllowed = principal.tenantPartnerID == partnerID && principal.permissions.contains(.viewDashboard)
        let adminAllowed = principal.role == .internalAdmin && principal.permissions.contains(.reviewPartners)
        guard partnerAllowed || adminAllowed else {
            appendAudit(principal, target: partnerID, operation: "dashboard_read", outcome: "denied", at: at)
            throw PartnerTenantAccessError.forbidden
        }
        appendAudit(principal, target: partnerID, operation: "dashboard_read", outcome: "allowed", at: at)
        return dashboardRecords[partnerID]
    }

    func finance(for partnerID: UUID, principal: PartnerPrincipal, at: Date = .now) throws -> LedgerMoney? {
        guard principal.role == .internalAdmin, principal.permissions.contains(.manageFinance), !principal.subjectID.isEmpty else {
            appendAudit(principal, target: partnerID, operation: "finance_read", outcome: "denied", at: at)
            throw PartnerTenantAccessError.forbidden
        }
        appendAudit(principal, target: partnerID, operation: "finance_read", outcome: "allowed", at: at)
        return dashboardRecords[partnerID]?.commissionBalance
    }

    func auditTrail() -> [TenantAccessAuditEvent] { audit }

    private func appendAudit(_ principal: PartnerPrincipal, target: UUID, operation: String, outcome: String, at: Date) {
        audit.append(.init(sequence: audit.count + 1, subjectID: principal.subjectID,
                           targetPartnerID: target, operation: operation, outcome: outcome, occurredAt: at))
    }
}
