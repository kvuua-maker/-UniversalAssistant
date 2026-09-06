import Foundation

struct ContextProvenance: Equatable, Codable, Sendable {
    let source: String
    let objectID: String
    let observedAt: Date
    let expiresAt: Date

    func isFresh(at date: Date) -> Bool { observedAt <= date && expiresAt > date }
}

struct ContextEntity: Equatable, Codable, Sendable {
    enum Kind: String, Codable, Sendable { case person, place, product, store, event, appointment, route, providerResult }
    let id: String
    let kind: Kind
    let displayName: String
    let phoneNumber: String?
    let latitude: Double?
    let longitude: Double?
    let actionID: String?
    let openReference: String?
    let provenance: ContextProvenance

    init(id: String, kind: Kind, displayName: String, phoneNumber: String?, provenance: ContextProvenance, latitude: Double? = nil, longitude: Double? = nil, actionID: String? = nil, openReference: String? = nil) {
        self.id = id; self.kind = kind; self.displayName = displayName; self.phoneNumber = phoneNumber
        self.provenance = provenance; self.latitude = latitude; self.longitude = longitude
        self.actionID = actionID; self.openReference = openReference
    }
}

struct ValidatedContextLocation: Equatable, Codable, Sendable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracyMeters: Double
    let provenance: ContextProvenance
}

struct ContextRoute: Equatable, Codable, Sendable {
    let destination: ContextEntity
    let provenance: ContextProvenance
}

struct ContextTask: Equatable, Codable, Sendable {
    let id: String
    let kind: String
    let provenance: ContextProvenance
}

enum ContextFollowUp: Equatable, Sendable {
    case confirm(ContextTask)
    case cheaper(resultIDs: [String])
    case navigate(ContextEntity)
    case call(ContextEntity)
    case reschedule(ContextEntity, offset: TimeInterval)
    case searchAlongRoute(category: String, route: ContextRoute)
    case unresolved
}

struct CurrentContext: Equatable, Codable, Sendable {
    private(set) var currentTime: Date? = nil
    private(set) var validatedLocation: ValidatedContextLocation? = nil
    private(set) var activeRoute: ContextRoute? = nil
    private(set) var nextCalendarEvent: ContextEntity? = nil
    private(set) var currentTask: ContextTask? = nil
    private(set) var resultEntities: [ContextEntity] = []
    private(set) var selectedEntity: ContextEntity? = nil
    private(set) var connectedServiceState: [String: Bool] = [:]
    private(set) var explicitPreferences: [String: String] = [:]
    private(set) var expiresAt: Date? = nil

    // Compatibility view for the original short-selection API.
    var lastResults: [String] { resultEntities.map(\.displayName) }
    var selectedResult: String? { selectedEntity?.displayName }

    mutating func update(
        now: Date,
        lifetime: TimeInterval = 300,
        location: ValidatedContextLocation? = nil,
        route: ContextRoute? = nil,
        nextEvent: ContextEntity? = nil,
        task: ContextTask? = nil,
        results: [ContextEntity]? = nil,
        services: [String: Bool]? = nil,
        preferences: [String: String]? = nil
    ) {
        expireStale(at: now)
        currentTime = now
        expiresAt = now.addingTimeInterval(max(1, lifetime))
        if let location, location.provenance.isFresh(at: now), location.horizontalAccuracyMeters >= 0 { validatedLocation = location }
        if let route, route.provenance.isFresh(at: now), route.destination.provenance.isFresh(at: now) { activeRoute = route }
        if let nextEvent, nextEvent.provenance.isFresh(at: now) { nextCalendarEvent = nextEvent }
        if let task, task.provenance.isFresh(at: now) { currentTask = task }
        if let results { resultEntities = Array(results.filter { $0.provenance.isFresh(at: now) }.prefix(20)); selectedEntity = nil }
        if let services { connectedServiceState = services }
        if let preferences { explicitPreferences = preferences }
    }

    mutating func store(results: [String], now: Date = .now, lifetime: TimeInterval = 300) {
        let provenance = ContextProvenance(source: "local-result", objectID: UUID().uuidString, observedAt: now, expiresAt: now.addingTimeInterval(lifetime))
        update(now: now, lifetime: lifetime, results: results.prefix(5).enumerated().map { .init(id: "legacy-\($0.offset)", kind: .providerResult, displayName: $0.element, phoneNumber: nil, provenance: provenance) })
    }

    mutating func resolve(_ command: StructuredCommand, now: Date = .now) -> String? {
        expireStale(at: now)
        guard [.contextualSelection, .open, .show].contains(command.intent), let ordinal = command.constraints.ordinal,
              resultEntities.indices.contains(ordinal - 1) else { return nil }
        selectedEntity = resultEntities[ordinal - 1]
        return selectedEntity?.displayName
    }

    @discardableResult
    mutating func select(entityID: String, now: Date = .now) -> ContextEntity? {
        expireStale(at: now)
        selectedEntity = resultEntities.first { $0.id == entityID }
        return selectedEntity
    }

    mutating func resolveFollowUp(_ phrase: String, now: Date = .now) -> ContextFollowUp {
        expireStale(at: now)
        let text = phrase.lowercased()
        if ["так", "да", "yes", "ja", "oui"].contains(text.trimmingCharacters(in: .whitespacesAndNewlines)), let currentTask { return .confirm(currentTask) }
        if text.contains("дешевш") { return resultEntities.isEmpty ? .unresolved : .cheaper(resultIDs: resultEntities.map(\.id)) }
        if text.contains("веди туди"), let target = selectedEntity ?? activeRoute?.destination { return .navigate(target) }
        if text.contains("подзвони їм"), let target = selectedEntity, target.phoneNumber != nil { return .call(target) }
        if text.contains("перенеси на годину"), let event = nextCalendarEvent { return .reschedule(event, offset: 3600) }
        if text.contains("по дорозі") && text.contains("аптек"), let route = activeRoute { return .searchAlongRoute(category: "pharmacy", route: route) }
        return .unresolved
    }

    func externalPayload(requiredFields: Set<String>, now: Date = .now) -> [String: String] {
        guard expiresAt.map({ $0 > now }) == true else { return [:] }
        var payload: [String: String] = [:]
        if requiredFields.contains("selected_entity_id"), let selectedEntity { payload["selected_entity_id"] = selectedEntity.id }
        if requiredFields.contains("route_destination_id"), let activeRoute { payload["route_destination_id"] = activeRoute.destination.id }
        if requiredFields.contains("task_id"), let currentTask { payload["task_id"] = currentTask.id }
        return payload
    }

    func confirmedPreference(_ key: String, now: Date = .now) -> String? {
        guard expiresAt.map({ $0 > now }) == true else { return nil }
        return explicitPreferences[key]
    }

    func savedPlace(named name: String, now: Date = .now) -> ContextEntity? {
        guard let id = confirmedPreference("place.\(name.lowercased())", now: now) else { return nil }
        return resultEntities.first { $0.id == id && $0.kind == .place && $0.provenance.isFresh(at: now) }
    }

    mutating func expireStale(at now: Date = .now) {
        guard expiresAt.map({ $0 > now }) == true else { reset(); return }
        if validatedLocation?.provenance.isFresh(at: now) == false { validatedLocation = nil }
        if activeRoute?.provenance.isFresh(at: now) == false || activeRoute?.destination.provenance.isFresh(at: now) == false { activeRoute = nil }
        if nextCalendarEvent?.provenance.isFresh(at: now) == false { nextCalendarEvent = nil }
        if currentTask?.provenance.isFresh(at: now) == false { currentTask = nil }
        resultEntities.removeAll { !$0.provenance.isFresh(at: now) }
        if let selectedEntity, !selectedEntity.provenance.isFresh(at: now) { self.selectedEntity = nil }
    }

    mutating func reset() {
        currentTime = nil; validatedLocation = nil; activeRoute = nil; nextCalendarEvent = nil
        currentTask = nil; resultEntities = []; selectedEntity = nil; connectedServiceState = [:]
        explicitPreferences = [:]; expiresAt = nil
    }
}


@MainActor
final class CurrentContextStore {
    private(set) var context = CurrentContext()
    private var consumedActionIDs: Set<String> = []
    func replaceResults(_ result: DeterministicResult, now: Date = .now, lifetime: TimeInterval = 300) {
        let expires = now.addingTimeInterval(lifetime)
        let actions = Dictionary(uniqueKeysWithValues: result.actions.map { ($0.id, $0) })
        let entities = result.facts.prefix(20).map { fact -> ContextEntity in
            let action = actions[fact.id]
            let provenance = ContextProvenance(source: fact.source ?? "local-result", objectID: fact.id, observedAt: fact.observedAt ?? now, expiresAt: expires)
            let phone = action?.destination?.scheme == "tel" ? action?.destination?.absoluteString.replacingOccurrences(of: "tel:", with: "") : nil
            return ContextEntity(id: fact.id, kind: .providerResult, displayName: fact.label, phoneNumber: phone, provenance: provenance, actionID: action?.id, openReference: action?.destination?.absoluteString)
        }
        context.update(now: now, lifetime: lifetime, results: entities)
        consumedActionIDs.removeAll()
    }
    func select(_ command: StructuredCommand, now: Date = .now) -> ContextEntity? {
        _ = context.resolve(command, now: now)
        return context.selectedEntity
    }
    func freshSelected(at now: Date = .now) -> ContextEntity? { context.expireStale(at: now); return context.selectedEntity }
    func consumeSelectedAction(now: Date = .now) -> URL? {
        context.expireStale(at: now)
        guard let selected = context.selectedEntity, let actionID = selected.actionID, !consumedActionIDs.contains(actionID), let reference = selected.openReference, let url = URL(string: reference) else { return nil }
        consumedActionIDs.insert(actionID)
        return url
    }
    func replaceRoute(origin: ValidatedLocation, destination: ValidatedLocation, destinationName: String, now: Date = .now, lifetime: TimeInterval = 300) {
        let expires = now.addingTimeInterval(lifetime)
        let destinationProvenance = ContextProvenance(source: "apple-geocoder", objectID: "destination-\(destination.sample.latitude),\(destination.sample.longitude)", observedAt: now, expiresAt: expires)
        let destinationEntity = ContextEntity(id: destinationProvenance.objectID, kind: .place, displayName: destinationName, phoneNumber: nil, provenance: destinationProvenance, latitude: destination.sample.latitude, longitude: destination.sample.longitude)
        let routeProvenance = ContextProvenance(source: "apple-maps", objectID: "route-\(UUID().uuidString)", observedAt: now, expiresAt: expires)
        let locationProvenance = ContextProvenance(source: "core-location", objectID: "origin-\(origin.sample.timestamp.timeIntervalSince1970)", observedAt: now, expiresAt: expires)
        context.update(now: now, lifetime: lifetime, location: .init(latitude: origin.sample.latitude, longitude: origin.sample.longitude, horizontalAccuracyMeters: origin.sample.horizontalAccuracy, provenance: locationProvenance), route: .init(destination: destinationEntity, provenance: routeProvenance))
    }
    func freshRoute(at now: Date = .now) -> (ValidatedContextLocation, ContextRoute)? {
        context.expireStale(at: now)
        guard let location = context.validatedLocation, let route = context.activeRoute else { return nil }
        return (location, route)
    }
    func reset() { context.reset(); consumedActionIDs.removeAll() }
}
