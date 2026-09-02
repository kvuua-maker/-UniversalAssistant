import Foundation

struct ActionAllowanceSnapshot: Codable, Equatable, Sendable {
    let accountState: UniversalAccountState
    private(set) var periodStartedAt: Date
    private(set) var completedTaskIDs: Set<String>

    init(accountState: UniversalAccountState, periodStartedAt: Date, completedTaskIDs: Set<String> = []) {
        self.accountState = accountState
        self.periodStartedAt = periodStartedAt
        self.completedTaskIDs = completedTaskIDs
    }

    func access(at now: Date, policy: AccountPolicy = .launch) -> AllowanceAccess {
        if accountState == .premium { return .allowed(remaining: nil) }
        let days = accountState == .guest ? policy.guestDurationDays : policy.freeCycleDays
        let limit = accountState == .guest ? policy.guestActionLimit : policy.freeActionLimit
        guard now < periodStartedAt.addingTimeInterval(Double(days) * 86_400) else {
            return accountState == .guest ? .registrationRequired : .allowed(remaining: limit)
        }
        let remaining = max(0, limit - completedTaskIDs.count)
        return remaining > 0 ? .allowed(remaining: remaining) : (accountState == .guest ? .registrationRequired : .cycleLimitReached)
    }

    mutating func recordCompletedTask(id: String, at now: Date, policy: AccountPolicy = .launch) throws {
        let taskID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !taskID.isEmpty else { throw AllowanceError.invalidTaskID }
        if completedTaskIDs.contains(taskID) { return }
        if accountState == .registeredFree,
           now >= periodStartedAt.addingTimeInterval(Double(policy.freeCycleDays) * 86_400) {
            periodStartedAt = now
            completedTaskIDs.removeAll(keepingCapacity: true)
        }
        guard case .allowed = access(at: now, policy: policy) else { throw AllowanceError.allowanceUnavailable }
        completedTaskIDs.insert(taskID)
    }
}

enum AllowanceAccess: Equatable, Sendable { case allowed(remaining: Int?), registrationRequired, cycleLimitReached }
enum AllowanceError: Error, Equatable, Sendable { case invalidTaskID, allowanceUnavailable }
