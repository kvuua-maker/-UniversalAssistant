import Foundation
import Testing
@testable import UniversalAssistant

struct StrongCurrentContextTests {
    private let now = Date(timeIntervalSince1970: 10_000)
    private func provenance(_ id: String, lifetime: TimeInterval = 300) -> ContextProvenance {
        .init(source: "provider.test", objectID: id, observedAt: now, expiresAt: now.addingTimeInterval(lifetime))
    }
    private func entity(_ id: String, kind: ContextEntity.Kind = .place, phone: String? = nil) -> ContextEntity {
        .init(id: id, kind: kind, displayName: id, phoneNumber: phone, provenance: provenance(id))
    }

    @Test func storesAllCanonicalFieldsWithExactProvenance() {
        var context = CurrentContext()
        let destination = entity("office")
        context.update(now: now, location: .init(latitude: 50.45, longitude: 30.52, horizontalAccuracyMeters: 12, provenance: provenance("location")), route: .init(destination: destination, provenance: provenance("route")), nextEvent: entity("meeting", kind: .event), task: .init(id: "task", kind: "commute", provenance: provenance("task")), results: [entity("one"), entity("two")], services: ["calendar": true], preferences: ["currency": "UAH"])
        #expect(context.currentTime == now); #expect(context.validatedLocation?.provenance.objectID == "location")
        #expect(context.activeRoute?.destination.id == "office"); #expect(context.nextCalendarEvent?.id == "meeting")
        #expect(context.currentTask?.id == "task"); #expect(context.resultEntities.map(\.id) == ["one", "two"])
        #expect(context.connectedServiceState["calendar"] == true); #expect(context.explicitPreferences["currency"] == "UAH")
    }

    @Test func canonicalNaturalFollowUpsResolveDeterministically() {
        var context = CurrentContext(); let destination = entity("office"); let shop = entity("shop", kind: .store, phone: "+380441234567")
        context.update(now: now, route: .init(destination: destination, provenance: provenance("route")), nextEvent: entity("meeting", kind: .event), results: [shop, destination])
        context.select(entityID: "shop", now: now)
        #expect(context.resolveFollowUp("А дешевше є?", now: now) == .cheaper(resultIDs: ["shop", "office"]))
        #expect(context.resolveFollowUp("Веди туди", now: now) == .navigate(shop))
        #expect(context.resolveFollowUp("Подзвони їм", now: now) == .call(shop))
        #expect(context.resolveFollowUp("Перенеси на годину", now: now) == .reschedule(entity("meeting", kind: .event), offset: 3600))
        #expect(context.resolveFollowUp("А по дорозі є аптека?", now: now) == .searchAlongRoute(category: "pharmacy", route: .init(destination: destination, provenance: provenance("route"))))
    }

    @Test func staleObjectsCannotBeReused() {
        var context = CurrentContext(); context.update(now: now, results: [entity("old")])
        #expect(context.resolveFollowUp("А дешевше є?", now: now.addingTimeInterval(301)) == .unresolved)
        #expect(context.resultEntities.isEmpty)
    }

    @Test func externalPayloadIsAllowlistedAndManualResetClearsEverything() {
        var context = CurrentContext(); context.update(now: now, route: .init(destination: entity("home"), provenance: provenance("route")), task: .init(id: "task", kind: "route", provenance: provenance("task")), results: [entity("shop")])
        context.select(entityID: "shop", now: now)
        let payload = context.externalPayload(requiredFields: ["selected_entity_id"], now: now)
        #expect(payload == ["selected_entity_id": "shop"])
        context.reset()
        #expect(context.currentTime == nil); #expect(context.resultEntities.isEmpty); #expect(context.externalPayload(requiredFields: ["selected_entity_id"], now: now).isEmpty)
    }

    @Test func invalidOrStaleLocationIsNotAccepted() {
        var context = CurrentContext()
        context.update(now: now, location: .init(latitude: 1, longitude: 2, horizontalAccuracyMeters: -1, provenance: provenance("bad")))
        #expect(context.validatedLocation == nil)
        context.update(now: now, location: .init(latitude: 1, longitude: 2, horizontalAccuracyMeters: 10, provenance: provenance("stale", lifetime: -1)))
        #expect(context.validatedLocation == nil)
    }
}
