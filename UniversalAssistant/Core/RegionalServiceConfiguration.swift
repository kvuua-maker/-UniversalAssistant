import Foundation

enum RegionalMeasurementSystem: String, Codable, Sendable { case metric, usCustomary, ukMixed }

struct RegionalEmergencyService: Equatable, Codable, Sendable {
    let kind: String
    let number: String
    let userInitiatedCallOnly: Bool
}

struct RegionalServiceProfile: Equatable, Codable, Sendable {
    let countryCode: String
    let defaultCurrencyCode: String
    let measurementSystem: RegionalMeasurementSystem
    let retailerProviderIDs: [String]
    let rideProviderIDs: [String]
    let ticketProviderIDs: [String]
    let emergencyServices: [RegionalEmergencyService]
}

struct RegionalServiceRegistry: Sendable {
    private let profiles: [String: RegionalServiceProfile]

    init(profiles: [RegionalServiceProfile] = Self.canonicalProfiles) {
        self.profiles = Dictionary(uniqueKeysWithValues: profiles.map { ($0.countryCode.uppercased(), $0) })
    }

    func profile(countryCode: String) -> RegionalServiceProfile? {
        profiles[countryCode.uppercased()]
    }

    static let canonicalProfiles: [RegionalServiceProfile] = [
        .init(countryCode: "UA", defaultCurrencyCode: "UAH", measurementSystem: .metric,
              retailerProviderIDs: UkrainianRetailerRegistry.records.map(\.id),
              rideProviderIDs: ["uklon", "uber", "bolt"], ticketProviderIDs: ["uz", "bus", "air"],
              emergencyServices: [
                .init(kind: "unified", number: "112", userInitiatedCallOnly: true),
                .init(kind: "fire", number: "101", userInitiatedCallOnly: true),
                .init(kind: "police", number: "102", userInitiatedCallOnly: true),
                .init(kind: "ambulance", number: "103", userInitiatedCallOnly: true),
                .init(kind: "gas", number: "104", userInitiatedCallOnly: true)
              ]),
        .init(countryCode: "DE", defaultCurrencyCode: "EUR", measurementSystem: .metric,
              retailerProviderIDs: [], rideProviderIDs: ["uber", "bolt"], ticketProviderIDs: ["rail", "bus", "air"],
              emergencyServices: [
                .init(kind: "police", number: "110", userInitiatedCallOnly: true),
                .init(kind: "fire_ambulance", number: "112", userInitiatedCallOnly: true)
              ]),
        .init(countryCode: "US", defaultCurrencyCode: "USD", measurementSystem: .usCustomary,
              retailerProviderIDs: [], rideProviderIDs: ["uber"], ticketProviderIDs: ["rail", "bus", "air"],
              emergencyServices: [.init(kind: "unified", number: "911", userInitiatedCallOnly: true)])
    ]
}

/// A single typed policy for user-initiated emergency telephone handoffs.
/// Semantic parsing resolves a concrete number before confirmation and the
/// executor validates that same payload instead of reparsing the utterance or
/// silently substituting a different destination.
enum CanonicalEmergencyNumberPolicy {
    private static let allServices = RegionalServiceRegistry.canonicalProfiles
        .flatMap(\.emergencyServices)

    static func explicitPermittedNumber(in normalizedText: String) -> String? {
        normalizedText
            .split(whereSeparator: { !$0.isNumber })
            .map(String.init)
            .first(where: isPermitted)
    }

    static func defaultNumber(countryCode: String? = Locale.current.region?.identifier) -> String? {
        let registry = RegionalServiceRegistry()
        let profile = countryCode.flatMap { registry.profile(countryCode: $0) }
            ?? registry.profile(countryCode: "UA")
        return profile?.emergencyServices.first(where: { $0.kind == "unified" })?.number
            ?? profile?.emergencyServices.first?.number
    }

    static func isPermitted(_ rawNumber: String) -> Bool {
        let digits = rawNumber.filter(\.isNumber)
        return !digits.isEmpty && allServices.contains { $0.number == digits && $0.userInitiatedCallOnly }
    }
}
