import Foundation

enum ProviderImplementationStatus: String, Codable, Sendable {
    case researched, adapterReady, credentialRequired, approvalRequired
    case deviceTestRequired, implementedTested, fallback, unsupported
}

struct CommerceProviderCapabilities: OptionSet, Codable, Sendable {
    let rawValue: UInt64
    static let search = Self(rawValue: 1 << 0)
    static let catalog = Self(rawValue: 1 << 1)
    static let exactProduct = Self(rawValue: 1 << 2)
    static let price = Self(rawValue: 1 << 3)
    static let availability = Self(rawValue: 1 << 4)
    static let shipping = Self(rawValue: 1 << 5)
    static let affiliateAttribution = Self(rawValue: 1 << 6)
    static let exactDeepLink = Self(rawValue: 1 << 7)
    static let appHandoff = Self(rawValue: 1 << 8)
}

struct ProviderCapabilityRecord: Identifiable, Equatable, Codable, Sendable {
    let id: String
    var displayName: String
    var regions: Set<String>
    var capabilities: CommerceProviderCapabilities
    var affiliateNetwork: String?
    var requiresCredentials: Bool
    var requiresOwnerRegistration: Bool
    var requiresApproval: Bool
    var rateLimitSummary: String?
    var restrictions: [String]
    var status: ProviderImplementationStatus
    var fallback: String?
    var lastOfficialVerification: Date?
    var enabled: Bool
}

actor ProviderCapabilityRegistry {
    private var records: [String: ProviderCapabilityRecord]

    init(records: [ProviderCapabilityRecord] = []) {
        self.records = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
    }

    func upsert(_ record: ProviderCapabilityRecord) { records[record.id] = record }
    func record(id: String) -> ProviderCapabilityRecord? { records[id] }

    func eligible(region: String, requiring capability: CommerceProviderCapabilities) -> [ProviderCapabilityRecord] {
        records.values.filter {
            $0.enabled && $0.regions.contains(region.uppercased())
                && $0.capabilities.contains(capability)
                && ![.unsupported, .credentialRequired, .approvalRequired].contains($0.status)
        }.sorted { $0.id < $1.id }
    }
}

protocol RetailProvider: Sendable {
    var providerID: String { get }
    func search(_ request: RetailSearchRequest) async throws -> [NormalizedOffer]
}

struct RetailSearchRequest: Equatable, Sendable {
    let identity: ProductIdentity
    var region: String = "UA"
    var limit: Int = 20

    func validated() throws -> Self {
        _ = try identity.validated()
        guard (1...50).contains(limit), region.count == 2 else { throw RetailProviderError.invalidRequest }
        return self
    }
}

enum RetailProviderError: Error, Equatable, Sendable { case invalidRequest, unavailable }
