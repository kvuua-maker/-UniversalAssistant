import Foundation

enum AffiliateProgramStatus: Int, Codable, CaseIterable, Sendable {
    case candidate, applicationRequired, applied, approved, credentialsReceived
    case implemented, testVerified, productionVerified, earningVerified
}

struct AffiliateProgramEvidence: Codable, Equatable, Sendable {
    let reference: String
    let kind: String
    let recordedAt: Date
    let provesConversionAttribution: Bool
}

struct AffiliateProgramRecord: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let providerID: String
    var status: AffiliateProgramStatus
    var evidence: [AffiliateProgramEvidence]
    var updatedAt: Date
}

enum AffiliateProgramRegistryError: Error, Equatable { case invalidRecord, invalidTransition, earningEvidenceRequired }

actor AffiliateProgramRegistry {
    private let store: LocalStore
    private let filename: String
    private var records: [String: AffiliateProgramRecord] = [:]

    init(store: LocalStore = .shared, filename: String = "affiliate-program-status.json") {
        self.store = store; self.filename = filename
    }

    func restore() async throws {
        records = Dictionary(uniqueKeysWithValues: (try await store.load([AffiliateProgramRecord].self, from: filename) ?? []).map { ($0.id, $0) })
    }

    func register(id: String, providerID: String, now: Date = .now) async throws -> AffiliateProgramRecord {
        guard !id.isEmpty, !providerID.isEmpty else { throw AffiliateProgramRegistryError.invalidRecord }
        if let existing = records[id] { return existing }
        let value = AffiliateProgramRecord(id: id, providerID: providerID, status: .candidate, evidence: [], updatedAt: now)
        records[id] = value; try await persist(); return value
    }

    func transition(id: String, to status: AffiliateProgramStatus, evidence: AffiliateProgramEvidence? = nil, now: Date = .now) async throws -> AffiliateProgramRecord {
        guard var value = records[id] else { throw AffiliateProgramRegistryError.invalidRecord }
        guard status.rawValue == value.status.rawValue + 1 else { throw AffiliateProgramRegistryError.invalidTransition }
        if status == .earningVerified, evidence?.provesConversionAttribution != true { throw AffiliateProgramRegistryError.earningEvidenceRequired }
        if let evidence { value.evidence.append(evidence) }
        value.status = status; value.updatedAt = now; records[id] = value
        try await persist(); return value
    }

    func record(id: String) -> AffiliateProgramRecord? { records[id] }

    private func persist() async throws {
        try await store.save(records.values.sorted { $0.id < $1.id }, as: filename)
    }
}
