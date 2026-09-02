import Foundation

enum ActionGraphEntityKind: String, CaseIterable, Codable, Sendable {
    case person, place, product, store, email, document, event, reminder, ticket, parcel, appointment, route, providerResult
}

enum UniversalActionKind: String, CaseIterable, Codable, Sendable {
    case search, open, show, call, message, route, createEvent, remind, compare, book, cancel, reschedule, track, share
}

enum GraphVerification: String, Codable, Sendable { case verified, unknown, unavailable }

struct ActionGraphEntity: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let kind: ActionGraphEntityKind
    let sourceProviderID: String
    let sourceObjectID: String
    let verification: GraphVerification
    let observedAt: Date
    let expiresAt: Date
    let relatedEntityIDs: [String]
    let nextActions: Set<UniversalActionKind>

    func isVerifiedFresh(at now: Date) -> Bool {
        verification == .verified && observedAt <= now && expiresAt > now
    }
}

struct ActionGraphCapability: Equatable, Codable, Sendable {
    let action: UniversalActionKind
    let acceptedInputs: Set<ActionGraphEntityKind>
    let output: ActionGraphEntityKind?
    let risk: ActionRisk
}

struct ActionGraphProvider: Equatable, Codable, Sendable {
    let id: String
    let capabilities: Set<UniversalActionKind>
}

struct ActionGraphInvocation: Equatable, Sendable {
    let action: UniversalActionKind
    let providerID: String
    let inputEntityIDs: [String]
    let risk: ActionRisk
}

enum UniversalActionGraphError: Error, Equatable {
    case duplicateEntity, duplicateProvider, unknownEntity, unknownProvider
    case unsupportedAction, incompatibleInput, staleOrUnverifiedInput, confirmationRequired
}

struct UniversalActionGraph: Sendable {
    private(set) var entities: [String: ActionGraphEntity] = [:]
    private(set) var providers: [String: ActionGraphProvider] = [:]
    private(set) var capabilities: [UniversalActionKind: ActionGraphCapability] = [:]

    mutating func register(_ capability: ActionGraphCapability) { capabilities[capability.action] = capability }

    mutating func register(_ provider: ActionGraphProvider) throws {
        guard providers[provider.id] == nil else { throw UniversalActionGraphError.duplicateProvider }
        providers[provider.id] = provider
    }

    mutating func add(_ entity: ActionGraphEntity) throws {
        guard entities[entity.id] == nil else { throw UniversalActionGraphError.duplicateEntity }
        entities[entity.id] = entity
    }

    func compose(
        action: UniversalActionKind,
        providerID: String,
        inputEntityIDs: [String],
        confirmed: Bool = false,
        now: Date = .now
    ) throws -> ActionGraphInvocation {
        guard let provider = providers[providerID] else { throw UniversalActionGraphError.unknownProvider }
        guard provider.capabilities.contains(action), let capability = capabilities[action] else { throw UniversalActionGraphError.unsupportedAction }
        let inputs = try inputEntityIDs.map { id in
            guard let entity = entities[id] else { throw UniversalActionGraphError.unknownEntity }
            return entity
        }
        guard inputs.allSatisfy({ capability.acceptedInputs.contains($0.kind) && $0.nextActions.contains(action) }) else {
            throw UniversalActionGraphError.incompatibleInput
        }
        guard inputs.allSatisfy({ $0.isVerifiedFresh(at: now) }) else { throw UniversalActionGraphError.staleOrUnverifiedInput }
        guard capability.risk != .consequential || confirmed else { throw UniversalActionGraphError.confirmationRequired }
        return .init(action: action, providerID: providerID, inputEntityIDs: inputEntityIDs, risk: capability.risk)
    }
}

extension UniversalActionGraph {
    static func canonical() -> Self {
        var graph = Self()
        let definitions: [(UniversalActionKind, Set<ActionGraphEntityKind>, ActionRisk)] = [
            (.search, [.email, .document, .place, .product, .store, .ticket, .parcel, .appointment], .informational),
            (.open, Set(ActionGraphEntityKind.allCases), .informational), (.show, Set(ActionGraphEntityKind.allCases), .informational),
            (.call, [.person, .store, .place, .providerResult], .consequential), (.message, [.person, .email, .providerResult], .consequential),
            (.route, [.place, .store, .event, .ticket, .parcel, .appointment, .providerResult], .informational),
            (.createEvent, [.email, .ticket, .appointment, .route, .providerResult], .reversible),
            (.remind, [.email, .event, .ticket, .parcel, .appointment, .route, .providerResult], .reversible),
            (.compare, [.product, .store, .ticket, .providerResult], .informational),
            (.book, [.ticket, .appointment, .providerResult], .consequential),
            (.cancel, [.event, .reminder, .ticket, .appointment, .providerResult], .consequential),
            (.reschedule, [.event, .appointment, .providerResult], .consequential),
            (.track, [.ticket, .parcel, .providerResult], .informational), (.share, Set(ActionGraphEntityKind.allCases), .consequential)
        ]
        for (action, inputs, risk) in definitions { graph.register(.init(action: action, acceptedInputs: inputs, output: nil, risk: risk)) }
        return graph
    }
}
