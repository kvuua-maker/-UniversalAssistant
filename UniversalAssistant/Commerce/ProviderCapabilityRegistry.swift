import Foundation

enum ProviderImplementationStatus: String, Codable, Sendable {
    case researched, adapterReady, credentialRequired, approvalRequired
    case deviceTestRequired, implementedTested, fallback, unsupported
    case fullyImplemented, fullyTested, partnerApprovalRequired, fallbackActive, temporarilyBroken
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
    static let cart = Self(rawValue: 1 << 9)
    static let checkoutHandoff = Self(rawValue: 1 << 10)
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
    var officialDocumentationURL: URL? = nil
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
                && [.adapterReady, .implementedTested, .fullyImplemented, .fullyTested, .fallback, .fallbackActive].contains($0.status)
        }.sorted { $0.id < $1.id }
    }
}

protocol RetailProvider: Sendable {
    var providerID: String { get }
    func search(_ request: RetailSearchRequest) async throws -> [NormalizedOffer]
}

enum RetailFulfillmentPreference: String, Equatable, Codable, Sendable {
    case pickup, delivery, either
}

struct RetailSearchLocation: Equatable, Codable, Sendable {
    let latitude: Double
    let longitude: Double
    var radiusMeters: Double

    func validated() throws -> Self {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude),
              (100...100_000).contains(radiusMeters) else { throw RetailProviderError.invalidRequest }
        return self
    }
}

struct RetailPriceRange: Equatable, Codable, Sendable {
    var minimum: Money?
    var maximum: Money?

    func validated() throws -> Self {
        guard minimum?.amount ?? 0 >= 0, maximum?.amount ?? 0 >= 0 else { throw RetailProviderError.invalidRequest }
        if let minimum, let maximum {
            guard minimum.currency == maximum.currency, minimum.amount <= maximum.amount else {
                throw RetailProviderError.invalidRequest
            }
        }
        return self
    }
}

struct RetailSearchRequest: Equatable, Sendable {
    let identity: ProductIdentity
    var region: String = "UA"
    var limit: Int = 20
    var priceRange: RetailPriceRange? = nil
    var fulfillment: RetailFulfillmentPreference = .either
    var location: RetailSearchLocation? = nil

    func validated() throws -> Self {
        _ = try identity.validated()
        guard (1...50).contains(limit), region.count == 2 else { throw RetailProviderError.invalidRequest }
        if let priceRange { _ = try priceRange.validated() }
        if let location { _ = try location.validated() }
        return self
    }
}

enum RetailProviderError: Error, Equatable, Sendable { case invalidRequest, unavailable }
