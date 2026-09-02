import Foundation
import Testing
@testable import UniversalAssistantServer

@Suite("Partner profile claim and truth controls")
struct PartnerProfileServiceTests {
    @Test func unclaimedPendingVerifiedFlowGatesPermittedProfileEditsAndAudits() async throws {
        let service = PartnerProfileService()
        let created = try await service.registerUnclaimed(partnerID: UUID(), name: "Cafe")
        #expect(created.state == .unclaimed)
        await #expect(throws: BusinessProfileError.verificationRequired) {
            try await service.update(created.id, name: "Fake", hours: nil,
                                     contacts: .init(phone: nil, website: nil, address: nil), actor: "claimant")
        }
        let pending = try await service.claim(created.id, claimant: "business-owner")
        #expect(pending.state == .pending)
        let verified = try await service.decide(created.id, approved: true, actor: "reviewer", evidenceReference: "evidence-1")
        #expect(verified.state == .verified)
        let hours = BusinessOpeningHours(weeklySchedule: ["mon": "09:00-18:00"], sourceReference: "partner", observedAt: .distantPast)
        let updated = try await service.update(created.id, name: "Cafe Official", hours: hours,
                                               contacts: .init(phone: "+380441234567", website: URL(string: "https://example.test"), address: "Kyiv"), actor: "business-owner")
        #expect(updated.hours == hours)
        #expect(updated.auditTrail.map(\.sequence) == Array(1...updated.auditTrail.count))
    }

    @Test func reportDoesNotAutomaticallyConvictAndSuspensionRequiresAuditedActorReason() async throws {
        let service = PartnerProfileService()
        let created = try await service.registerUnclaimed(partnerID: UUID(), name: "Service")
        _ = try await service.claim(created.id, claimant: "owner")
        _ = try await service.decide(created.id, approved: true, actor: "reviewer", evidenceReference: "verified-doc")
        let reported = try await service.report(created.id, category: "outdated_hours", evidenceReference: "screen-1")
        #expect(reported.state == .verified)
        #expect(reported.reports.count == 1)
        let suspended = try await service.suspend(created.id, actor: "risk-admin", reason: "confirmed_abuse")
        #expect(suspended.state == .suspended)
        #expect(suspended.auditTrail.last?.reason == "confirmed_abuse")
    }

    @Test func insecureContactAndUnverifiedClaimFailClosed() async throws {
        let service = PartnerProfileService()
        let created = try await service.registerUnclaimed(partnerID: UUID(), name: "Store")
        _ = try await service.claim(created.id, claimant: "owner")
        _ = try await service.decide(created.id, approved: true, actor: "reviewer", evidenceReference: "verified-doc")
        await #expect(throws: BusinessProfileError.invalidProfile) {
            try await service.update(created.id, name: "Store", hours: nil,
                                     contacts: .init(phone: nil, website: URL(string: "http://example.test"), address: nil), actor: "owner")
        }
        await #expect(throws: BusinessProfileError.invalidTransition) {
            try await service.claim(created.id, claimant: "other")
        }
    }
}
