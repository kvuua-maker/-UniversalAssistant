import Foundation

/// Immutable evidence entering the production corridor. Only the canonical
/// resolver may turn this evidence into a StructuredCommand.
struct CanonicalRequestEnvelope: Sendable {
    enum Source: String, Sendable { case typed, voice, appIntent, continuation }

    let requestID: UUID
    let source: Source
    let originalText: String
    let appleFinalTranscript: String?
    let appleAlternatives: [String]
    let appleSegmentAlternatives: [String]
    let partialHistory: [String]
    let groqTranscript: String?
    let language: CommandLanguage
}

enum ExecutionRoom: String, CaseIterable, Sendable {
    case systemApps
    case communication
    case personal
    case documentsCamera
    case media
    case location
    case commerce
    case servicesBooking
    case jobsDelivery
    case web
    case compound
}

enum RouteTerminalStrategy: String, Sendable {
    case execute
    case present
    case exactWeb
    case clarify
    case confirm
    case systemInstruction
    case compound
}

/// One frozen production decision. Rooms receive this plan and are forbidden
/// from parsing, selecting a different provider, or calling the top-level
/// routing policy again.
struct RoutePlan: Equatable, Sendable {
    let command: StructuredCommand
    let room: ExecutionRoom
    let primaryMechanism: String
    let providerID: String?
    let terminalStrategy: RouteTerminalStrategy
    let routingDecision: CanonicalRoutingDecision
    let atomicPlans: [RoutePlan]
}

/// Read-only facade over the established capability/provider registries.
/// It contains availability facts only; it never parses user text.
struct ProductionCapabilityRegistryFacade: Sendable {
    let configuredRestaurantReservationProviderIDs: Set<String>

    init(configuredRestaurantReservationProviderIDs: Set<String> = []) {
        self.configuredRestaurantReservationProviderIDs = configuredRestaurantReservationProviderIDs
    }

    var hasRestaurantReservationInventory: Bool {
        !configuredRestaurantReservationProviderIDs.isEmpty
    }

    func verifiedProvider(id: String?) -> OfficialPublicProviderHandoff? {
        guard let id else { return nil }
        return OfficialPublicProviderHandoffRegistry.records.first(where: { $0.id == id })
    }
}

enum ProductionEngineReachabilityState: String, Sendable { case room, exactPublicRoute, notConfigured }

struct ProductionEngineReachabilityRecord: Sendable {
    let engineID: String
    let room: ExecutionRoom
    let state: ProductionEngineReachabilityState
    let terminalMechanism: String
}

enum ProductionEngineReachability {
    /// Capability modules are never counted as user-reachable merely because
    /// their types compile. Each entry names the shipped room or the truthful
    /// deterministic public route used when live provider prerequisites are absent.
    static let records: [ProductionEngineReachabilityRecord] = [
        .init(engineID: "HotelSearchEngine", room: .servicesBooking, state: .exactPublicRoute, terminalMechanism: "booking_official_search"),
        .init(engineID: "TicketEngine", room: .servicesBooking, state: .exactPublicRoute, terminalMechanism: "official_ticket_or_site_search"),
        .init(engineID: "RideComparisonEngine", room: .servicesBooking, state: .exactPublicRoute, terminalMechanism: "exact_web_no_inventory_claim"),
        .init(engineID: "TravelPlanEngine", room: .servicesBooking, state: .exactPublicRoute, terminalMechanism: "exact_web_travel_composition"),
        .init(engineID: "JobsDiscoveryEngine", room: .jobsDelivery, state: .room, terminalMechanism: "jobs_vertical"),
        .init(engineID: "ParcelDeliveryEngine", room: .jobsDelivery, state: .room, terminalMechanism: "carrier_route"),
        .init(engineID: "FoodDeliveryComparisonEngine", room: .jobsDelivery, state: .exactPublicRoute, terminalMechanism: "official_provider_search"),
        .init(engineID: "AppointmentEngine", room: .servicesBooking, state: .exactPublicRoute, terminalMechanism: "local_service_search"),
        .init(engineID: "GovernmentLocalServicesEngine", room: .servicesBooking, state: .exactPublicRoute, terminalMechanism: "official_service_search"),
        .init(engineID: "GmailEmailProvider", room: .communication, state: .notConfigured, terminalMechanism: "mail_composer_without_google_account_claim"),
        .init(engineID: "UniversalAudioDeviceCoordinator", room: .media, state: .room, terminalMechanism: "public_audio_route"),
        .init(engineID: "CommerceSearchEngine", room: .commerce, state: .exactPublicRoute, terminalMechanism: "official_or_exact_web")
    ]
}

/// The only production ownership router. It is pure: one resolved command in,
/// one frozen plan out. Execution rooms cannot call it recursively.
struct SingleCorridorRouter: Sendable {
    private let policy: CanonicalRoutingPolicy
    private let capabilities: ProductionCapabilityRegistryFacade
    private let decisionObserved: (@Sendable (UUID) -> Void)?

    init(
        policy: CanonicalRoutingPolicy = .init(),
        capabilities: ProductionCapabilityRegistryFacade = .init(),
        decisionObserved: (@Sendable (UUID) -> Void)? = nil
    ) {
        self.policy = policy
        self.capabilities = capabilities
        self.decisionObserved = decisionObserved
    }

    func plan(_ command: StructuredCommand) -> RoutePlan {
        if command.intent == .multiStep {
            return .init(
                command: command, room: .compound, primaryMechanism: "pre_routed_dependency_graph",
                providerID: nil, terminalStrategy: .clarify,
                routingDecision: .init(lane: .clarification, providerID: nil,
                                       reason: "compound_requires_pre_resolved_atomic_commands",
                                       allowsMultipleResults: false), atomicPlans: []
            )
        }
        return planAtomic(command)
    }

    func planCompound(container: StructuredCommand, atomicCommands: [StructuredCommand]) -> RoutePlan {
        precondition(container.intent == .multiStep)
        let atomicPlans = atomicCommands
            .filter { $0.intent != .unknown && $0.intent != .multiStep }
            .map(planAtomic)
        return .init(
            command: container, room: .compound, primaryMechanism: "pre_routed_dependency_graph",
            providerID: nil, terminalStrategy: atomicPlans.isEmpty ? .clarify : .compound,
            routingDecision: .init(lane: atomicPlans.isEmpty ? .clarification : .specialized,
                                   providerID: nil, reason: "compound_atomic_commands_pre_resolved",
                                   allowsMultipleResults: false), atomicPlans: atomicPlans
        )
    }

    private func planAtomic(_ command: StructuredCommand) -> RoutePlan {
        decisionObserved?(command.id)
        let decision = policy.decide(command)
        let room = room(for: command, decision: decision)
        let terminal = terminalStrategy(for: command, decision: decision, room: room)
        return .init(
            command: command,
            room: room,
            primaryMechanism: mechanism(for: command, decision: decision, room: room),
            providerID: decision.providerID,
            terminalStrategy: terminal,
            routingDecision: decision,
            atomicPlans: []
        )
    }

    private func room(for command: StructuredCommand, decision: CanonicalRoutingDecision) -> ExecutionRoom {
        if command.intent == .multiStep { return .compound }
        if command.entities["provider_domain"] == "jobs" || decision.lane == .jobs {
            return .jobsDelivery
        }
        if command.intent == .productSearch,
           command.entities["identity_strength"] == "exact",
           command.entities["gtin"] != nil {
            return .web
        }
        switch command.intent {
        case .contactCall, .messageCompose, .emergency:
            return .communication
        case .contactLookup, .calendarCreate, .calendarQuery, .calendarUpdate, .calendarDelete,
             .reminderCreate, .reminderQuery, .reminderComplete, .reminderDelete, .shoppingList,
             .noteCreate, .noteQuery, .photoSearch, .undo:
            return .personal
        case .cameraCapture, .fileSearch, .translation:
            return .documentsCamera
        case .mediaSearch, .podcastSearch, .musicRecognition, .audioRecord:
            return .media
        case .weather, .placeSearch, .restaurantSearch, .navigation, .routeSearch,
             .routeAwareSearch, .publicTransport, .transportRoute:
            return .location
        case .productSearch, .fashionDiscovery, .groceryBasket:
            return .commerce
        case .reservation, .hotelSearch, .serviceSearch, .taxiSearch, .taxiCompare,
             .ticketSearch, .ticketPurchaseHandoff, .travelPlan:
            return .servicesBooking
        case .cancel where command.entities["reservation_operation"] == "cancel":
            return .servicesBooking
        case .parcelTrack:
            return .jobsDelivery
        case .webSearch:
            return .web
        case .unknown where decision.lane == .informationalWeb || command.entities["protected_system_command"] != "true":
            return .web
        default:
            if command.entities["provider_domain"] == "jobs" || decision.lane == .jobs || decision.lane == .delivery {
                return .jobsDelivery
            }
            if decision.lane == .informationalWeb || decision.lane == .providerBoundary { return .web }
            return .systemApps
        }
    }

    private func terminalStrategy(
        for command: StructuredCommand,
        decision: CanonicalRoutingDecision,
        room: ExecutionRoom
    ) -> RouteTerminalStrategy {
        if command.needsClarification || decision.lane == .clarification { return .clarify }
        if room == .compound { return .compound }
        if room == .web { return .exactWeb }
        if decision.providerID == "events.karabas",
           !KarabasOfficialCityRoute.preservesEveryConstraint(in: command) {
            return .exactWeb
        }
        if command.intent == .reservation && !capabilities.hasRestaurantReservationInventory {
            return command.entities["reservation_operation"] == "modify" ? .systemInstruction : .exactWeb
        }
        if command.intent == .cancel,
           command.entities["reservation_operation"] == "cancel",
           !capabilities.hasRestaurantReservationInventory {
            return .systemInstruction
        }
        if command.intent == .travelPlan { return .exactWeb }
        if decision.lane == .providerBoundary { return .exactWeb }
        return .execute
    }

    private func mechanism(
        for command: StructuredCommand,
        decision: CanonicalRoutingDecision,
        room: ExecutionRoom
    ) -> String {
        if room == .web || command.intent == .travelPlan ||
            (command.intent == .reservation && !capabilities.hasRestaurantReservationInventory) ||
            (decision.providerID == "events.karabas" && !KarabasOfficialCityRoute.preservesEveryConstraint(in: command)) {
            return decision.providerID == nil ? "google_search_exact" : "official_or_site_restricted_exact"
        }
        if let provider = capabilities.verifiedProvider(id: decision.providerID) { return provider.id }
        switch room {
        case .communication: return "public_communication_handoff"
        case .personal: return "apple_personal_framework"
        case .documentsCamera: return "apple_document_framework"
        case .media: return "public_media_framework"
        case .location: return command.intent == .weather ? "weatherkit" : "mapkit"
        case .systemApps: return "apple_public_system_capability"
        case .commerce: return "official_commerce_destination"
        case .servicesBooking: return "official_service_destination"
        case .jobsDelivery: return "jobs_delivery_provider"
        case .compound: return "pre_routed_dependency_graph"
        case .web: return "google_search_exact"
        }
    }
}
