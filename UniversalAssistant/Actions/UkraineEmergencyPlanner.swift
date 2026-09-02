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
