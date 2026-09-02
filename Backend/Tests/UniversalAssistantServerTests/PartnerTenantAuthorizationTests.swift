import Foundation
import Testing
@testable import UniversalAssistantServer

private func dashboardRecord(_ partner: UUID) -> PartnerDashboardRecord {
    .init(partnerID: partner, profileStatus: .active, integrationHealth: "ACTIVE_HEALTHY",
          attributedConversions: 3, commissionBalance: .init(amount: 12, currencyCode: "USD"))
}

@Suite("Partner tenant authorization and isolation")
struct PartnerTenantAuthorizationTests {
    @Test func partnerACannotReadOrWritePartnerB() async throws {
        let store = PartnerTenantDataStore(), a = UUID(), b = UUID()
        let admin = PartnerPrincipal(subjectID: "admin", tenantPartnerID: nil, role: .internalAdmin,
                                     permissions: [.reviewPartners])
        try await store.upsert(dashboardRecord(b), principal: admin)
        let principalA = PartnerPrincipal(subjectID: "user-a", tenantPartnerID: a, role: .partnerOperator,
                                          permissions: [.viewDashboard, .manageIntegration])
        await #expect(throws: PartnerTenantAccessError.forbidden) {
            try await store.dashboard(for: b, principal: principalA)
        }
        await #expect(throws: PartnerTenantAccessError.forbidden) {
            try await store.upsert(dashboardRecord(b), principal: principalA)
        }
        #expect(await store.auditTrail().filter { $0.outcome == "denied" }.count == 2)
    }

    @Test func partnerReadsOnlyOwnAllowedDashboardAndNeverFinanceAdminPath() async throws {
        let store = PartnerTenantDataStore(), partner = UUID()
        let admin = PartnerPrincipal(subjectID: "admin", tenantPartnerID: nil, role: .internalAdmin,
                                     permissions: [.reviewPartners])
        try await store.upsert(dashboardRecord(partner), principal: admin)
        let viewer = PartnerPrincipal(subjectID: "viewer", tenantPartnerID: partner, role: .partnerViewer,
                                      permissions: [.viewDashboard])
        #expect(try await store.dashboard(for: partner, principal: viewer)?.partnerID == partner)
        await #expect(throws: PartnerTenantAccessError.forbidden) {
            try await store.finance(for: partner, principal: viewer)
        }
    }

    @Test func highRiskAdminFinanceAccessRequiresPermissionAndIsAudited() async throws {
        let store = PartnerTenantDataStore(), partner = UUID()
        let writer = PartnerPrincipal(subjectID: "admin-writer", tenantPartnerID: nil, role: .internalAdmin,
                                      permissions: [.reviewPartners])
        try await store.upsert(dashboardRecord(partner), principal: writer)
        let finance = PartnerPrincipal(subjectID: "finance-admin", tenantPartnerID: nil, role: .internalAdmin,
                                       permissions: [.manageFinance])
        #expect(try await store.finance(for: partner, principal: finance)?.amount == 12)
        #expect(await store.auditTrail().last?.operation == "finance_read")
        #expect(await store.auditTrail().last?.subjectID == "finance-admin")
    }
}
