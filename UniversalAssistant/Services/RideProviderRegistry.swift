import Foundation

enum RideProviderStatus: String, Codable, Sendable {
    case researched, credentialRequired, approvalRequired, adapterReady, unsupported
}

struct RideProviderCapabilities: Equatable, Sendable {
    let providerID: String
    let status: RideProviderStatus
    let supportsLivePrice: Bool
    let supportsLivePickupETA: Bool
    let supportsLiveAvailability: Bool
    let supportsRoutePrefillHandoff: Bool
    let officialDocumentation: URL
    let lastVerified: Date

    var canSupplyComparisonEvidence: Bool {
        [.adapterReady].contains(status) && (supportsLivePrice || supportsLivePickupETA || supportsLiveAvailability)
    }
}

struct RideProviderRegistry: Sendable {
    private let entries: [RideProviderCapabilities]

    init(entries: [RideProviderCapabilities] = Self.verifiedEntries) { self.entries = entries }

    func capabilities(for providerID: String) -> RideProviderCapabilities? {
        entries.first { $0.providerID == providerID }
    }

    static let verifiedEntries: [RideProviderCapabilities] = {
        let verified = Date(timeIntervalSince1970: 1_788_220_800) // 2026-09-01 UTC
        return [
            .init(providerID: "uber", status: .credentialRequired,
                  supportsLivePrice: false, supportsLivePickupETA: false, supportsLiveAvailability: false,
                  supportsRoutePrefillHandoff: true,
                  officialDocumentation: URL(string: "https://developer.uber.com/docs/riders/ride-requests/tutorials/deep-links/introduction")!,
                  lastVerified: verified),
            .init(providerID: "bolt", status: .researched,
                  supportsLivePrice: false, supportsLivePickupETA: false, supportsLiveAvailability: false,
                  supportsRoutePrefillHandoff: false,
                  officialDocumentation: URL(string: "https://bolt.eu/en/support/articles/115002296213/")!,
                  lastVerified: verified),
            .init(providerID: "uklon", status: .researched,
                  supportsLivePrice: false, supportsLivePickupETA: false, supportsLiveAvailability: false,
                  supportsRoutePrefillHandoff: false,
                  officialDocumentation: URL(string: "https://uklon.com.ua/")!,
                  lastVerified: verified)
        ]
    }()
}

struct RideHandoffLocation: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let nickname: String
    let address: String

    var isValid: Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude) &&
        !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum RideHandoffError: Error, Equatable, Sendable { case missingCredential, invalidLocation, unsupportedProvider }

struct UberRideHandoffBuilder: Sendable {
    func destination(clientID: String, pickup: RideHandoffLocation, dropoff: RideHandoffLocation) throws -> URL {
        guard !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RideHandoffError.missingCredential
        }
        guard pickup.isValid, dropoff.isValid else { throw RideHandoffError.invalidLocation }
        var components = URLComponents(string: "https://m.uber.com/looking")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "pickup[latitude]", value: String(pickup.latitude)),
            .init(name: "pickup[longitude]", value: String(pickup.longitude)),
            .init(name: "pickup[nickname]", value: pickup.nickname),
            .init(name: "pickup[formatted_address]", value: pickup.address),
            .init(name: "dropoff[latitude]", value: String(dropoff.latitude)),
            .init(name: "dropoff[longitude]", value: String(dropoff.longitude)),
            .init(name: "dropoff[nickname]", value: dropoff.nickname),
            .init(name: "dropoff[formatted_address]", value: dropoff.address)
        ]
        guard let result = components.url else { throw RideHandoffError.invalidLocation }
        return result
    }
}
