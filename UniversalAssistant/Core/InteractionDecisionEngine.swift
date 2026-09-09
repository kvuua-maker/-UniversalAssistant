import Foundation

enum InteractionPattern: Equatable, Sendable {
    case clarify
    case directAction
    case compactAcknowledgement
    case fullScreenResult
    case confirmation
}

struct InteractionDecision: Equatable, Sendable {
    let pattern: InteractionPattern
    let reason: String
}

protocol InteractionDeciding: Sendable {
    func decide(for command: StructuredCommand) -> InteractionDecision
}

struct InteractionDecisionEngine: InteractionDeciding {
    func decide(for command: StructuredCommand) -> InteractionDecision {
        if command.needsClarification {
            return .init(pattern: .clarify, reason: "missing_or_ambiguous_intent")
        }
        if requiresConfirmation(command) {
            return .init(pattern: .confirmation, reason: "material_consequence_or_system_safety")
        }
        if requiresVisualSelection(command.intent) {
            return .init(pattern: .fullScreenResult, reason: "comparison_or_selection_required")
        }
        if supportsDirectAction(command.intent) {
            return .init(pattern: .directAction, reason: "clear_low_friction_action")
        }
        return .init(pattern: .compactAcknowledgement, reason: "structured_request_recognized")
    }

    private func requiresConfirmation(_ command: StructuredCommand) -> Bool {
        // Search/discovery must first produce a concrete provider result. Confirmation
        // belongs to the verified booking/purchase action, not to discovery itself.
        if [.ticketPurchaseHandoff, .reservation].contains(command.intent) { return false }
        return command.risk == .consequential || command.risk == .emergency || [
            .calendarDelete, .cancel
        ].contains(command.intent)
    }

    private func requiresVisualSelection(_ intent: CommandIntent) -> Bool {
        [
            .productSearch, .fashionDiscovery, .groceryBasket, .placeSearch, .serviceSearch, .restaurantSearch,
            .taxiSearch, .taxiCompare, .routeSearch, .routeAwareSearch, .ticketSearch,
            .hotelSearch, .travelPlan
        ].contains(intent)
    }

    private func supportsDirectAction(_ intent: CommandIntent) -> Bool {
        [
            .open, .appAction, .deviceAction, .navigation, .calendarCreate, .calendarUpdate,
            .reminderCreate, .noteCreate, .contactCall, .messageCompose, .audioRecord, .undo
        ].contains(intent)
    }
}
