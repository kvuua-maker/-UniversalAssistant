import Foundation

enum AssistantResultState: Equatable, Sendable {
    case idle
    case recognized(ResultSummary)
    case clarification(ResultSummary)
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
        case .calendarCreate, .calendarQuery, .calendarUpdate, .calendarDelete: "calendar"
        case .reminderCreate, .reminderQuery: "checkmark.circle.fill"
        case .unknown: "questionmark.bubble.fill"
        default: "sparkles"
        }
    }
}
