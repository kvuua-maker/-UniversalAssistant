import Foundation

enum AssistantResultState: Equatable, Sendable {
    case idle
    case processing
    case recognized(ResultSummary)
    case weather(WeatherSnapshot)
    case webHandoff(WebHandoffResult)
    case clarification(ResultSummary)
    case actionRequired(ActionRequiredSummary)
    case failure(UserFacingFailure)
    case expanded(ResultSummary)
}

struct WebHandoffResult: Equatable, Sendable { let query: String; let destination: URL }

struct ActionRequiredSummary: Equatable, Sendable {
    let prompt: String
    let choices: [String]
}

struct UserFacingFailure: Equatable, Sendable {
    let message: String
    let recoveryAction: String?
}

struct ResultSummary: Equatable, Sendable {
    let request: String
    let intent: CommandIntent
    let risk: ActionRisk

    var symbolName: String {
        switch intent {
        case .emergency: "cross.case.fill"
        case .navigation, .routeSearch, .routeAwareSearch: "location.fill"
        case .weather: "cloud.sun.fill"
        case .productSearch, .groceryBasket, .fashionDiscovery: "bag.fill"
        case .serviceSearch: "wrench.and.screwdriver.fill"
        case .calendarCreate, .calendarQuery, .calendarUpdate, .calendarDelete: "calendar"
        case .reminderCreate, .reminderQuery: "checkmark.circle.fill"
        case .unknown: "questionmark.bubble.fill"
        default: "sparkles"
        }
    }
}
