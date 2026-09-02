import Foundation

enum UkraineEmergencyService: String, CaseIterable, Sendable {
    case unified = "112"
    case fireAndRescue = "101"
    case police = "102"
    case ambulance = "103"
    case gasEmergency = "104"
}

enum EmergencyHandoffState: String, Equatable, Sendable {
    case readyForUserCall
    case unavailableOutsideUkraine
}

struct EmergencyHandoffPlan: Equatable, Sendable {
    let service: UkraineEmergencyService
    let state: EmergencyHandoffState
    let destination: URL?
    let claimsDispatch: Bool
    let claimsLocationShared: Bool
    let reason: String
}

struct UkraineEmergencyPlanner: Sendable {
    func plan(service: UkraineEmergencyService, regionCode: String) -> EmergencyHandoffPlan {
        guard regionCode.uppercased() == "UA" else {
            return .init(service: service, state: .unavailableOutsideUkraine, destination: nil,
                         claimsDispatch: false, claimsLocationShared: false,
                         reason: "ukraine_v1_region_boundary")
        }
        return .init(service: service, state: .readyForUserCall,
                     destination: URL(string: "tel:\(service.rawValue)"),
                     claimsDispatch: false, claimsLocationShared: false,
                     reason: "user_visible_system_phone_handoff")
    }
}

struct EmergencyLocationPresentation: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracyMeters: Double
    let bestAvailableAddress: String?
    let shareText: String
    let mapURL: URL
    let claimsAutomaticTransmission: Bool
}

enum EmergencyLocationError: Error, Equatable { case invalidOrStaleLocation }

struct EmergencyLocationPresenter: Sendable {
    func presentation(
        location: ValidatedContextLocation,
        address: String?,
        now: Date = .now
    ) throws -> EmergencyLocationPresentation {
        guard (-90...90).contains(location.latitude), (-180...180).contains(location.longitude),
              location.horizontalAccuracyMeters >= 0, location.provenance.isFresh(at: now),
              let mapURL = URL(string: "https://maps.apple.com/?ll=\(location.latitude),\(location.longitude)") else {
            throw EmergencyLocationError.invalidOrStaleLocation
        }
        let cleanAddress = address?.trimmingCharacters(in: .whitespacesAndNewlines)
        let usableAddress = cleanAddress?.isEmpty == false ? cleanAddress : nil
        let text = ["Location: \(location.latitude), \(location.longitude)",
                    "Accuracy: ±\(Int(location.horizontalAccuracyMeters.rounded())) m",
                    usableAddress].compactMap { $0 }.joined(separator: "\n")
        return .init(latitude: location.latitude, longitude: location.longitude,
                     horizontalAccuracyMeters: location.horizontalAccuracyMeters,
                     bestAvailableAddress: usableAddress, shareText: text, mapURL: mapURL,
                     claimsAutomaticTransmission: false)
    }
}
