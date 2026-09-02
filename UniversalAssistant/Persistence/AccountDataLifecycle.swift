import Foundation

enum AccountCleanupKind: String, CaseIterable, Codable, Sendable {
    case proactiveJobs, pushTokens, providerConnections, cloudData, localAccountSession
}
enum CleanupStatus: Equatable, Sendable { case completed, failed(reason: String) }
struct CleanupResult: Equatable, Sendable { let kind: AccountCleanupKind; let status: CleanupStatus }

protocol AccountCleanupOperation: Sendable {
    var kind: AccountCleanupKind { get }
    func execute() async throws
}

struct AccountDeletionReport: Equatable, Sendable {
    let results: [CleanupResult]
    var isComplete: Bool { results.allSatisfy { if case .completed = $0.status { true } else { false } } }
}

struct AccountDeletionCoordinator: Sendable {
    func delete(using operations: [any AccountCleanupOperation]) async -> AccountDeletionReport {
        let unique = Dictionary(operations.map { ($0.kind, $0) }, uniquingKeysWith: { first, _ in first })
        let results = await withTaskGroup(of: CleanupResult.self, returning: [CleanupResult].self) { group in
            for (kind, operation) in unique {
                group.addTask {
                    do { try await operation.execute(); return .init(kind: kind, status: .completed) }
                    catch { return .init(kind: kind, status: .failed(reason: "cleanup_failed")) }
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        return .init(results: results.sorted { $0.kind.rawValue < $1.kind.rawValue })
    }
}

struct AssistantOwnedDataExport: Codable, Equatable, Sendable {
    let exportedAt: Date
    let schemaVersion: Int
    let records: [SyncRecord]
    func json() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
