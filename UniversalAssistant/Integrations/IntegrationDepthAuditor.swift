import Foundation

enum CapabilityDepth: Int, Comparable, Sendable {
    case unsupported, open, contextHandoff, readSearch, writeAction, transaction, monitorProactive
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct IntegrationDepthFinding: Equatable, Sendable {
    let appID: String
    let maximumClaimableDepth: CapabilityDepth
    let productionVerified: Bool
    let reason: String
}

struct IntegrationDepthAuditor: Sendable {
    func audit(_ record: AppCapabilityRecord) -> IntegrationDepthFinding {
        let depth: CapabilityDepth
        if record.capabilities.contains(.order) || record.capabilities.contains(.book) {
            depth = .transaction
        } else if !record.capabilities.intersection([.create, .update, .send, .play, .pause]).isEmpty,
                  !record.mechanisms.isDisjoint(with: [.api, .sdk, .appIntent, .shortcut]) {
            depth = .writeAction
        } else if !record.capabilities.intersection([.read, .search]).isEmpty,
                  !record.mechanisms.isDisjoint(with: [.api, .sdk]) {
            depth = .readSearch
        } else if record.capabilities.contains(.openExactContext) {
            depth = .contextHandoff
        } else if record.capabilities.contains(.openApp) {
            depth = .open
        } else {
            depth = .unsupported
        }
        let productionVerified = record.testStatus == .implemented || record.testStatus == .simulatorVerified
        return .init(appID: record.id, maximumClaimableDepth: depth,
                     productionVerified: productionVerified,
                     reason: productionVerified ? "production_evidence_recorded" : "device_or_external_evidence_pending")
    }
}
