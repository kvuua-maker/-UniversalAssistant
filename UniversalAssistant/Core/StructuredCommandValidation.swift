import Foundation

enum CommandValidationIssue: String, Error, Equatable, Sendable {
    case unresolvedIntent, ambiguousTarget, missingTarget, missingDateTime
    case missingLocation, permissionDenied, invalidRisk
}

struct CommandExecutionContext: Equatable, Sendable {
    var targetResolved = true
    var dateTimeResolved = true
    var locationAvailable = true
    var permissionGranted = true
    var isAmbiguous = false
}

struct ValidatedStructuredCommand: Equatable, Sendable {
    let command: StructuredCommand
    let validatedAt: Date
}

struct StructuredCommandValidator: Sendable {
    func validate(_ command: StructuredCommand, context: CommandExecutionContext = .init(), now: Date = .now) throws -> ValidatedStructuredCommand {
        guard command.intent != .unknown, !command.needsClarification else { throw CommandValidationIssue.unresolvedIntent }
        guard !context.isAmbiguous else { throw CommandValidationIssue.ambiguousTarget }
        guard context.permissionGranted else { throw CommandValidationIssue.permissionDenied }
        if requiresTarget(command.intent), !context.targetResolved { throw CommandValidationIssue.missingTarget }
        if requiresDateTime(command.intent), !context.dateTimeResolved { throw CommandValidationIssue.missingDateTime }
        if requiresLocation(command.intent), !context.locationAvailable { throw CommandValidationIssue.missingLocation }
        if requiresConfirmation(command.intent), command.risk == .informational,
           ![.reservation, .ticketPurchaseHandoff, .calendarDelete, .cancel].contains(command.intent) {
            throw CommandValidationIssue.invalidRisk
        }
        return .init(command: command, validatedAt: now)
    }

    private func requiresTarget(_ intent: CommandIntent) -> Bool {
        [.open, .appAction, .contactCall, .messageCompose, .calendarUpdate, .calendarDelete,
         .reservation, .cancel, .navigation].contains(intent)
    }

    private func requiresDateTime(_ intent: CommandIntent) -> Bool {
        [.calendarCreate, .calendarUpdate, .reminderCreate, .reservation, .travelPlan].contains(intent)
    }

    private func requiresLocation(_ intent: CommandIntent) -> Bool {
        [.placeSearch, .restaurantSearch, .serviceSearch, .taxiSearch, .taxiCompare,
         .navigation, .routeSearch, .routeAwareSearch, .publicTransport, .transportRoute].contains(intent)
    }

    private func requiresConfirmation(_ intent: CommandIntent) -> Bool {
        [.reservation, .ticketPurchaseHandoff, .calendarDelete, .cancel, .emergency].contains(intent)
    }
}

struct ConsequentialCommandGate: Sendable {
    private let validator = StructuredCommandValidator()

    func prepare(_ command: StructuredCommand, context: CommandExecutionContext, confirmed: Bool) throws -> ValidatedStructuredCommand {
        let validated = try validator.validate(command, context: context)
        let consequential = command.risk == .consequential || command.risk == .emergency ||
            [.reservation, .ticketPurchaseHandoff, .calendarDelete, .cancel].contains(command.intent)
        guard !consequential || confirmed else { throw CommandValidationIssue.invalidRisk }
        return validated
    }
}
