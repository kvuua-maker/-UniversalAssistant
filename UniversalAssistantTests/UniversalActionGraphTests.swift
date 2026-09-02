import Foundation
import Testing
@testable import UniversalAssistant

struct UniversalActionGraphTests {
    private let now = Date(timeIntervalSince1970: 20_000)
    private func entity(_ id: String, _ kind: ActionGraphEntityKind, actions: Set<UniversalActionKind>) -> ActionGraphEntity {
        .init(id: id, kind: kind, sourceProviderID: "source", sourceObjectID: "object-\(id)", verification: .verified, observedAt: now, expiresAt: now.addingTimeInterval(300), relatedEntityIDs: [], nextActions: actions)
    }

    @Test func canonicalEntityAndActionTaxonomiesAreComplete() {
        #expect(Set(ActionGraphEntityKind.allCases) == [.person, .place, .product, .store, .email, .document, .event, .reminder, .ticket, .parcel, .appointment, .route, .providerResult])
        #expect(Set(UniversalActionKind.allCases) == [.search, .open, .show, .call, .message, .route, .createEvent, .remind, .compare, .book, .cancel, .reschedule, .track, .share])
    }

    @Test func verifiedResultsComposeIntoCanonicalTypedJourneys() throws {
        var graph = UniversalActionGraph.canonical()
        try graph.register(.init(id: "system", capabilities: Set(UniversalActionKind.allCases)))
        let inputs = [
            entity("email", .email, actions: [.createEvent]), entity("address", .place, actions: [.route]),
            entity("product", .product, actions: [.compare]), entity("store", .store, actions: [.route]),
            entity("ticket", .ticket, actions: [.route, .remind]), entity("parcel", .parcel, actions: [.track, .route]),
            entity("appointment", .appointment, actions: [.createEvent, .route, .remind])
        ]
        for value in inputs { try graph.add(value) }
        #expect(try graph.compose(action: .createEvent, providerID: "system", inputEntityIDs: ["email"], now: now).inputEntityIDs == ["email"])
        #expect(try graph.compose(action: .route, providerID: "system", inputEntityIDs: ["address"], now: now).inputEntityIDs == ["address"])
        #expect(try graph.compose(action: .compare, providerID: "system", inputEntityIDs: ["product"], now: now).inputEntityIDs == ["product"])
        #expect(try graph.compose(action: .remind, providerID: "system", inputEntityIDs: ["ticket"], now: now).inputEntityIDs == ["ticket"])
        #expect(try graph.compose(action: .track, providerID: "system", inputEntityIDs: ["parcel"], now: now).inputEntityIDs == ["parcel"])
        #expect(try graph.compose(action: .createEvent, providerID: "system", inputEntityIDs: ["appointment"], now: now).inputEntityIDs == ["appointment"])
    }

    @Test func staleUnknownAndIncompatibleInputsNeverCompose() throws {
        var graph = UniversalActionGraph.canonical(); try graph.register(.init(id: "maps", capabilities: [.route]))
        var stale = entity("stale", .place, actions: [.route])
        stale = .init(id: stale.id, kind: stale.kind, sourceProviderID: stale.sourceProviderID, sourceObjectID: stale.sourceObjectID, verification: .verified, observedAt: stale.observedAt, expiresAt: now.addingTimeInterval(-1), relatedEntityIDs: [], nextActions: stale.nextActions)
        try graph.add(stale); try graph.add(entity("person", .person, actions: [.route]))
        #expect(throws: UniversalActionGraphError.staleOrUnverifiedInput) { try graph.compose(action: .route, providerID: "maps", inputEntityIDs: ["stale"], now: now) }
        #expect(throws: UniversalActionGraphError.incompatibleInput) { try graph.compose(action: .route, providerID: "maps", inputEntityIDs: ["person"], now: now) }
    }

    @Test func consequentialActionRequiresConfirmation() throws {
        var graph = UniversalActionGraph.canonical(); try graph.register(.init(id: "booking", capabilities: [.book]))
        try graph.add(entity("slot", .appointment, actions: [.book]))
        #expect(throws: UniversalActionGraphError.confirmationRequired) { try graph.compose(action: .book, providerID: "booking", inputEntityIDs: ["slot"], now: now) }
        #expect(try graph.compose(action: .book, providerID: "booking", inputEntityIDs: ["slot"], confirmed: true, now: now).risk == .consequential)
    }

    @Test func providerRegistrationMakesCapabilityReusableWithoutFlowRewrite() throws {
        var graph = UniversalActionGraph.canonical()
        try graph.register(.init(id: "provider-a", capabilities: [.track])); try graph.register(.init(id: "provider-b", capabilities: [.track]))
        try graph.add(entity("parcel", .parcel, actions: [.track]))
        #expect(try graph.compose(action: .track, providerID: "provider-a", inputEntityIDs: ["parcel"], now: now).providerID == "provider-a")
        #expect(try graph.compose(action: .track, providerID: "provider-b", inputEntityIDs: ["parcel"], now: now).providerID == "provider-b")
    }
}
