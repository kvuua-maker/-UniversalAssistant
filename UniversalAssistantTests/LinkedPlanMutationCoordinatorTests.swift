import Foundation
import Testing
@testable import UniversalAssistant

private actor LinkedPlanStoreSpy: LinkedPlanMutating {
    var plans: [LinkedPlan]; var removed: [(LinkedArtifactKind, String)] = []; var updated: [(LinkedArtifactKind, String, Date)] = []
    init(_ plans: [LinkedPlan]) { self.plans = plans }
    func matching(_ query: String, day: DateInterval?) -> [LinkedPlan] { plans.filter { $0.title.lowercased().contains(query) && (day?.contains($0.startsAt) ?? true) } }
    func cancelPlan(id: String) -> String { id }
    func reschedulePlan(id: String, to date: Date) throws -> LinkedPlan {
        guard let index = plans.firstIndex(where: { $0.id == id }) else { throw LinkedPlanMutationError.notFound }
        plans[index].startsAt = date; return plans[index]
    }
    func removeLinkedArtifact(kind: LinkedArtifactKind, id: String) { removed.append((kind, id)) }
    func updateLinkedArtifact(kind: LinkedArtifactKind, id: String, planStart: Date) { updated.append((kind, id, planStart)) }
    func counts() -> (Int, Int) { (removed.count, updated.count) }
}

struct LinkedPlanMutationCoordinatorTests {
    private func plan(_ id: String = "dentist") -> LinkedPlan { .init(id: id, title: "стоматолог", startsAt: .now, linkedArtifacts: [.departureReminder: "r1", .routeWatch: "w1", .proactiveRule: "p1"]) }

    @Test func clearCancellationRemovesOnlyLinkedArtifactsAfterConfirmation() async throws {
        let store = LinkedPlanStoreSpy([plan()]); let coordinator = LinkedPlanMutationCoordinator(store: store)
        await #expect(throws: LinkedPlanMutationError.confirmationRequired) { try await coordinator.cancel(query: "стоматолог", confirmed: false) }
        #expect(try await coordinator.cancel(query: "стоматолог", confirmed: true).id == "dentist")
        let counts = await store.counts(); #expect(counts.0 == 3); #expect(counts.1 == 0)
    }

    @Test func rescheduleMutatesSamePlanAndUpdatesLinkedArtifactsWithoutDuplicate() async throws {
        let store = LinkedPlanStoreSpy([plan()]); let date = Date(timeIntervalSince1970: 50_000)
        let result = try await LinkedPlanMutationCoordinator(store: store).reschedule(query: "стоматолог", to: date, confirmed: true)
        #expect(result.id == "dentist"); #expect(result.startsAt == date)
        let counts = await store.counts(); #expect(counts.0 == 0); #expect(counts.1 == 3)
    }

    @Test func ambiguityNeverChoosesArbitrarily() async {
        let store = LinkedPlanStoreSpy([plan("a"), plan("b")])
        await #expect(throws: LinkedPlanMutationError.ambiguous) { try await LinkedPlanMutationCoordinator(store: store).cancel(query: "стоматолог", confirmed: true) }
    }
}
