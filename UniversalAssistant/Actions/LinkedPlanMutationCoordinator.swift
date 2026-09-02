import Foundation

enum LinkedArtifactKind: String, Codable, Hashable, Sendable { case departureReminder, routeWatch, proactiveRule }
struct LinkedPlan: Identifiable, Equatable, Codable, Sendable {
    let id: String
    var title: String
    var startsAt: Date
    var linkedArtifacts: [LinkedArtifactKind: String]
}
enum LinkedPlanMutationError: Error, Equatable, Sendable { case notFound, ambiguous, confirmationRequired, unverifiedMutation }

protocol LinkedPlanMutating: Sendable {
    func matching(_ normalizedQuery: String, day: DateInterval?) async throws -> [LinkedPlan]
    func cancelPlan(id: String) async throws -> String
    func reschedulePlan(id: String, to: Date) async throws -> LinkedPlan
    func removeLinkedArtifact(kind: LinkedArtifactKind, id: String) async throws
    func updateLinkedArtifact(kind: LinkedArtifactKind, id: String, planStart: Date) async throws
}

struct LinkedPlanMutationCoordinator: Sendable {
    let store: any LinkedPlanMutating

    func cancel(query: String, day: DateInterval? = nil, confirmed: Bool) async throws -> LinkedPlan {
        guard confirmed else { throw LinkedPlanMutationError.confirmationRequired }
        let plan = try await unique(query, day: day)
        guard try await store.cancelPlan(id: plan.id) == plan.id else { throw LinkedPlanMutationError.unverifiedMutation }
        for (kind, id) in plan.linkedArtifacts { try await store.removeLinkedArtifact(kind: kind, id: id) }
        return plan
    }

    func reschedule(query: String, day: DateInterval? = nil, to date: Date, confirmed: Bool) async throws -> LinkedPlan {
        guard confirmed else { throw LinkedPlanMutationError.confirmationRequired }
        let plan = try await unique(query, day: day)
        let updated = try await store.reschedulePlan(id: plan.id, to: date)
        guard updated.id == plan.id, updated.startsAt == date else { throw LinkedPlanMutationError.unverifiedMutation }
        for (kind, id) in plan.linkedArtifacts { try await store.updateLinkedArtifact(kind: kind, id: id, planStart: date) }
        return updated
    }

    private func unique(_ query: String, day: DateInterval?) async throws -> LinkedPlan {
        let normalized = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = try await store.matching(normalized, day: day)
        guard !matches.isEmpty else { throw LinkedPlanMutationError.notFound }
        guard matches.count == 1 else { throw LinkedPlanMutationError.ambiguous }
        return matches[0]
    }
}
