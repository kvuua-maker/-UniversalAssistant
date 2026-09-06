import Foundation
import Testing
@testable import UniversalAssistant

private actor ContextEventKitProbe: EventKitCommandExecuting {
    private(set) var selectedID: String?
    func execute(_ command: StructuredCommand) async throws -> EventKitExecutionResult {
        selectedID = command.entities["selected_item_id"]
        return .init(kind: .calendar, operation: .updated, title: command.entities["subject"] ?? "Event", detail: "updated", itemCount: 1)
    }
}

@MainActor
struct ProductionContextFollowUpBindingTests {
    private let now = Date()
    private func result(id: String, title: String, destination: String?) throws -> DeterministicResult {
        try DeterministicResultComposer().compose(primaryAnswer: "Found", facts: [.init(id: id, label: title, value: "verified", state: .verified, source: "local", observedAt: now, priority: 100)], actions: destination.flatMap { URL(string: $0) }.map { [.init(id: id, title: "Open", kind: .open, destination: $0)] } ?? [])
    }
    private func select(_ store: CurrentContextStore) {
        _ = store.select(.init(originalText: "first", normalizedText: "first", language: .en, intent: .contextualSelection, constraints: .init(ordinal: 1)), now: now)
    }
    @Test func selectedContactCallsAndReplayIsRejected() async throws {
        let store = CurrentContextStore(); store.replaceResults(try result(id: "contact-1", title: "Mama", destination: "tel:+380441234567"), now: now); select(store)
        let executor = ProductionCanonicalCapabilityExecutor(currentContext: store)
        let command = StructuredCommand(originalText: "Call them", normalizedText: "call them", language: .en, intent: .contactCall)
        guard case let .handoff(value) = try await executor.execute(command) else { Issue.record("Expected call handoff"); return }
        #expect(value.destination.scheme == "tel")
        await #expect(throws: CanonicalCapabilityExecutionError.unavailable("context_action_unavailable_or_replayed")) { try await executor.execute(command) }
    }
    @Test func selectedPlaceNavigatesAndReplayIsRejected() async throws {
        let store = CurrentContextStore(); store.replaceResults(try result(id: "place-1", title: "Cafe", destination: "https://maps.apple.com/?q=Cafe"), now: now); select(store)
        let executor = ProductionCanonicalCapabilityExecutor(currentContext: store)
        let command = StructuredCommand(originalText: "Navigate there", normalizedText: "navigate there", language: .en, intent: .navigation)
        guard case .handoff = try await executor.execute(command) else { Issue.record("Expected navigation handoff"); return }
        await #expect(throws: CanonicalCapabilityExecutionError.unavailable("context_action_unavailable_or_replayed")) { try await executor.execute(command) }
    }
    @Test func selectedEventReschedulesUsingExactAuthoritativeID() async throws {
        let store = CurrentContextStore(); store.replaceResults(try result(id: "event-42", title: "Dentist", destination: nil), now: now); select(store)
        let probe = ContextEventKitProbe(); let executor = ProductionCanonicalCapabilityExecutor(currentContext: store, eventKit: probe)
        let command = StructuredCommand(originalText: "Move it tomorrow at 15:00", normalizedText: "move it tomorrow at 15:00", language: .en, intent: .calendarUpdate)
        guard case let .result(value) = try await executor.execute(command) else { Issue.record("Expected typed update result"); return }
        #expect(value.facts.first?.id == "event-42"); #expect(await probe.selectedID == "event-42")
    }
    @Test func staleMissingAndUnsupportedContextFailTruthfully() async throws {
        let store = CurrentContextStore(); store.replaceResults(try result(id: "old", title: "Old", destination: nil), now: now.addingTimeInterval(-400), lifetime: 1)
        let executor = ProductionCanonicalCapabilityExecutor(currentContext: store)
        let call = StructuredCommand(originalText: "Call", normalizedText: "call", language: .en, intent: .contactCall)
        await #expect(throws: CanonicalCapabilityExecutionError.missingParameter("active_result_context")) { try await executor.execute(call) }
        let show = StructuredCommand(originalText: "Show", normalizedText: "show", language: .en, intent: .contextualSelection)
        await #expect(throws: CanonicalCapabilityExecutionError.missingParameter("active_result_context")) { try await executor.execute(show) }
    }
}
