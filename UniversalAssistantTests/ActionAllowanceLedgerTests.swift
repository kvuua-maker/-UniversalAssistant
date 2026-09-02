import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Deterministic action allowance")
struct ActionAllowanceLedgerTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func coherentTaskAndFollowupsChargeExactlyOnce() throws {
        var ledger = ActionAllowanceSnapshot(accountState: .guest, periodStartedAt: start)
        try ledger.recordCompletedTask(id: "task-1", at: start)
        try ledger.recordCompletedTask(id: "task-1", at: start.addingTimeInterval(10))
        #expect(ledger.access(at: start) == .allowed(remaining: 14))
    }

    @Test func guestStopsAtEarlierActionOrTimeBoundary() throws {
        var ledger = ActionAllowanceSnapshot(accountState: .guest, periodStartedAt: start)
        for index in 0..<15 { try ledger.recordCompletedTask(id: "task-\(index)", at: start) }
        #expect(ledger.access(at: start) == .registrationRequired)
        let expired = ActionAllowanceSnapshot(accountState: .guest, periodStartedAt: start)
        #expect(expired.access(at: start.addingTimeInterval(7 * 86_400)) == .registrationRequired)
    }

    @Test func premiumHasNoOrdinaryActionCeiling() throws {
        var ledger = ActionAllowanceSnapshot(accountState: .premium, periodStartedAt: start)
        for index in 0..<100 { try ledger.recordCompletedTask(id: "task-\(index)", at: start) }
        #expect(ledger.access(at: start) == .allowed(remaining: nil))
    }

    @Test func registeredFreeCycleResetsWithoutAccumulatingUnusedActions() throws {
        var ledger = ActionAllowanceSnapshot(accountState: .registeredFree, periodStartedAt: start)
        try ledger.recordCompletedTask(id: "old", at: start)
        let nextCycle = start.addingTimeInterval(7 * 86_400)
        try ledger.recordCompletedTask(id: "new", at: nextCycle)
        #expect(ledger.access(at: nextCycle) == .allowed(remaining: 29))
    }
}
