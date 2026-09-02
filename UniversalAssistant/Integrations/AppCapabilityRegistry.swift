import Foundation

struct AppCapabilities: OptionSet, Codable, Sendable {
    let rawValue: UInt64
    static let openApp = Self(rawValue: 1 << 0), openExactContext = Self(rawValue: 1 << 1)
    static let search = Self(rawValue: 1 << 2), read = Self(rawValue: 1 << 3)
    static let create = Self(rawValue: 1 << 4), update = Self(rawValue: 1 << 5)
    static let send = Self(rawValue: 1 << 6), play = Self(rawValue: 1 << 7)
    static let pause = Self(rawValue: 1 << 8), navigate = Self(rawValue: 1 << 9)
    static let book = Self(rawValue: 1 << 10), order = Self(rawValue: 1 << 11)
    static let paymentHandoff = Self(rawValue: 1 << 12)
}
enum AppIntegrationMechanism: String, Codable, Sendable { case appIntent, shortcut, urlScheme, universalLink, sdk, api, openOnly }
enum AppCapabilityTestStatus: String, Codable, Sendable { case documented, implemented, simulatorVerified, deviceTestRequired, credentialRequired, unavailable }

struct AppCapabilityRecord: Identifiable, Codable, Equatable, Sendable {
    let id: String; let displayName: String; let bundleIdentifier: String?
    let regions: Set<String>; let minimumVersion: String?
    let capabilities: AppCapabilities; let mechanisms: Set<AppIntegrationMechanism>
    let supportedActions: Set<String>; let authenticationRequired: Bool
    let limitations: [String]; let fallback: AppCapabilities
    let testStatus: AppCapabilityTestStatus
    let officialDocumentationURL: URL?; let lastOfficialVerification: Date?
}
enum AppCapabilityRegistryError: Error, Equatable, Sendable { case invalidRecord, unsupportedCapability }

actor AppCapabilityRegistry {
    private var records: [String: AppCapabilityRecord] = [:]
    init(records: [AppCapabilityRecord] = []) throws { for record in records { try Self.validate(record); self.records[record.id] = record } }
    func upsert(_ record: AppCapabilityRecord) throws { try Self.validate(record); records[record.id] = record }
    func record(id: String) -> AppCapabilityRecord? { records[id] }
    func eligible(region: String, capability: AppCapabilities, installedVersion: String? = nil) -> [AppCapabilityRecord] {
        records.values.filter { record in
            guard record.regions.contains(region.uppercased()), record.capabilities.contains(capability),
                  record.testStatus != .unavailable else { return false }
            if let minimum = record.minimumVersion { guard let installedVersion, installedVersion.compare(minimum, options: .numeric) != .orderedAscending else { return false } }
            return true
        }.sorted { $0.id < $1.id }
    }
    func deepestRoute(appID: String, capability: AppCapabilities) throws -> (AppIntegrationMechanism, AppCapabilityTestStatus) {
        guard let record = records[appID], record.capabilities.contains(capability) else { throw AppCapabilityRegistryError.unsupportedCapability }
        let order: [AppIntegrationMechanism] = [.api, .sdk, .appIntent, .shortcut, .universalLink, .urlScheme, .openOnly]
        guard let mechanism = order.first(where: record.mechanisms.contains) else { throw AppCapabilityRegistryError.unsupportedCapability }
        return (mechanism, record.testStatus)
    }
    private static func validate(_ record: AppCapabilityRecord) throws {
        guard !record.id.isEmpty, !record.displayName.isEmpty, !record.regions.isEmpty,
              !record.capabilities.isEmpty, !record.mechanisms.isEmpty,
              record.officialDocumentationURL?.scheme == "https", record.lastOfficialVerification != nil else { throw AppCapabilityRegistryError.invalidRecord }
        if record.mechanisms == [.openOnly] && record.capabilities != [.openApp] { throw AppCapabilityRegistryError.invalidRecord }
        if record.capabilities.contains(.openExactContext) && record.mechanisms.isDisjoint(with: [.appIntent, .shortcut, .urlScheme, .universalLink, .sdk, .api]) { throw AppCapabilityRegistryError.invalidRecord }
    }
}
