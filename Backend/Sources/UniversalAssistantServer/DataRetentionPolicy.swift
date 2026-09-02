import Foundation

public enum RetentionDataClass: String, Codable, CaseIterable, Sendable {
    case operationalLog, analytics, userAccount, businessRecord, backup, deletedAccountResidual
}

public struct RetentionRule: Codable, Equatable, Sendable {
    public let dataClass: RetentionDataClass
    public let maximumAge: TimeInterval?
    public let eraseOnAccountDeletion: Bool
    public let legalHoldAllowed: Bool
}

public struct RetentionRecord: Codable, Equatable, Sendable {
    public let recordID: String
    public let dataClass: RetentionDataClass
    public let createdAt: Date
    public let accountDeletedAt: Date?
    public let legalHold: Bool
}

public enum RetentionDecision: String, Codable, Sendable { case retain, erase }
public enum RetentionPolicyError: Error, Equatable, Sendable { case invalidRules, invalidRecord }

public struct DataRetentionPolicy: Sendable {
    private let rules: [RetentionDataClass: RetentionRule]

    public init(rules: [RetentionRule]) throws {
        guard rules.count == RetentionDataClass.allCases.count,
              Set(rules.map(\.dataClass)).count == rules.count,
              rules.allSatisfy({ $0.maximumAge.map { $0 > 0 } ?? true }) else {
            throw RetentionPolicyError.invalidRules
        }
        self.rules = Dictionary(uniqueKeysWithValues: rules.map { ($0.dataClass, $0) })
    }

    public func decision(for record: RetentionRecord, now: Date = .now) throws -> RetentionDecision {
        guard !record.recordID.isEmpty, record.createdAt <= now,
              let rule = rules[record.dataClass] else { throw RetentionPolicyError.invalidRecord }
        if record.legalHold && rule.legalHoldAllowed { return .retain }
        if rule.eraseOnAccountDeletion, let deletion = record.accountDeletedAt {
            let residualAge = now.timeIntervalSince(deletion)
            return residualAge >= (rule.maximumAge ?? 0) ? .erase : .retain
        }
        guard let maximumAge = rule.maximumAge else { return .retain }
        return now.timeIntervalSince(record.createdAt) >= maximumAge ? .erase : .retain
    }

    public func expiredIDs(in records: [RetentionRecord], now: Date = .now) throws -> [String] {
        try records.filter { try decision(for: $0, now: now) == .erase }
            .map(\.recordID).sorted()
    }
}
