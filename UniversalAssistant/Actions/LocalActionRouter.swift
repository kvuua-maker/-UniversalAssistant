import Foundation

enum LocalIntegrationTarget: String, Equatable, Sendable {
    case eventKitCalendar
    case eventKitReminders
    case contacts
    case systemShareHandoff
    case internalAudioRecorder
    case unsupported
}

enum IntegrationDepth: String, Equatable, Sendable {
    case direct
    case handoff
    case unavailable
}

struct LocalActionRoute: Equatable, Sendable {
    let target: LocalIntegrationTarget
    let depth: IntegrationDepth
    let reason: String
}

struct LocalActionRouter: Sendable {
    func route(_ command: StructuredCommand) -> LocalActionRoute {
        switch command.intent {
        case .calendarCreate, .calendarQuery, .calendarUpdate, .calendarDelete:
            .init(target: .eventKitCalendar, depth: .direct, reason: "public_eventkit_calendar")
        case .reminderCreate, .reminderQuery, .shoppingList:
            .init(target: .eventKitReminders, depth: .direct, reason: "system_first_reminders")
        case .contactLookup, .contactCall:
            .init(target: .contacts, depth: .direct, reason: "public_contacts_framework")
        case .noteCreate, .noteQuery:
            .init(target: .systemShareHandoff, depth: .handoff, reason: "no_public_unrestricted_notes_api")
        case .audioRecord:
            .init(target: .internalAudioRecorder, depth: .direct, reason: "public_apple_audio_api")
        default:
            .init(target: .unsupported, depth: .unavailable, reason: "no_verified_local_adapter")
        }
    }
}
