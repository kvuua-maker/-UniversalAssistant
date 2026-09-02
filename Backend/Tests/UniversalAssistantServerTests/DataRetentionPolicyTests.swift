import Foundation
import Testing
@testable import UniversalAssistantServer

@Suite("Data retention policy")
struct DataRetentionPolicyTests {
    private func policy() throws -> DataRetentionPolicy {
        try DataRetentionPolicy(rules: [
            .init(dataClass: .operationalLog, maximumAge: 30 * 86_400, eraseOnAccountDeletion: false, legalHoldAllowed: true),
            .init(dataClass: .analytics, maximumAge: 90 * 86_400, eraseOnAccountDeletion: false, legalHoldAllowed: false),
            .init(dataClass: .userAccount, maximumAge: 30 * 86_400, eraseOnAccountDeletion: true, legalHoldAllowed: true),
            .init(dataClass: .businessRecord, maximumAge: nil, eraseOnAccountDeletion: false, legalHoldAllowed: true),
            .init(dataClass: .backup, maximumAge: 30 * 86_400, eraseOnAccountDeletion: false, legalHoldAllowed: true),
            .init(dataClass: .deletedAccountResidual, maximumAge: 30 * 86_400, eraseOnAccountDeletion: true, legalHoldAllowed: true)
        ])
    }

    @Test func expiredBoundedDataIsSelectedDeterministically() throws {
        let now = Date(timeIntervalSince1970: 10_000_000), policy = try policy()
        let old = now.addingTimeInterval(-91 * 86_400)
        let records = [
            RetentionRecord(recordID: "analytics", dataClass: .analytics, createdAt: old, accountDeletedAt: nil, legalHold: false),
            RetentionRecord(recordID: "business", dataClass: .businessRecord, createdAt: old, accountDeletedAt: nil, legalHold: false),
            RetentionRecord(recordID: "log-held", dataClass: .operationalLog, createdAt: old, accountDeletedAt: nil, legalHold: true)
        ]
        #expect(try policy.expiredIDs(in: records, now: now) == ["analytics"])
    }

    @Test func deletedAccountResidualExpiresButActiveAccountDoesNotUseCreationAge() throws {
        let now = Date(timeIntervalSince1970: 20_000_000), policy = try policy()
        let old = now.addingTimeInterval(-100 * 86_400)
        let recentDeletion = now.addingTimeInterval(-10 * 86_400)
        let oldDeletion = now.addingTimeInterval(-31 * 86_400)
        #expect(try policy.decision(for: .init(
            recordID: "recent", dataClass: .userAccount, createdAt: old,
            accountDeletedAt: recentDeletion, legalHold: false
        ), now: now) == .retain)
        #expect(try policy.decision(for: .init(
            recordID: "expired", dataClass: .userAccount, createdAt: old,
            accountDeletedAt: oldDeletion, legalHold: false
        ), now: now) == .erase)
    }
}
