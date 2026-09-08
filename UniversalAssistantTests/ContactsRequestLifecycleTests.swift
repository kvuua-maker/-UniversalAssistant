import Foundation
import Testing
@testable import UniversalAssistant

private struct ContactAuthorizationStub: ContactAuthorizing {
    let status: ContactAuthorizationState
    let granted: Bool
    func currentStatus() -> ContactAuthorizationState { status }
    func requestAccess() async throws -> Bool { granted }
}

private final class ContactStoreStub: ContactStoreQuerying, @unchecked Sendable {
    let delay: TimeInterval
    let values: [ContactCandidate]
    init(delay: TimeInterval = 0, values: [ContactCandidate] = []) { self.delay = delay; self.values = values }
    func contacts(matching name: String) throws -> [ContactCandidate] {
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        return values
    }
    func contact(identifier: String) throws -> ContactCandidate? { values.first { $0.identifier == identifier } }
}

private struct FailingContactStoreStub: ContactStoreQuerying {
    func contacts(matching name: String) throws -> [ContactCandidate] {
        throw NSError(domain: "CNErrorDomain", code: 100)
    }
    func contact(identifier: String) throws -> ContactCandidate? {
        throw NSError(domain: "CNErrorDomain", code: 100)
    }
}

@MainActor
private final class SequencedCapabilityExecutor: CanonicalCapabilityExecuting {
    private var calls = 0
    func execute(_ command: StructuredCommand) async throws -> CapabilityExecutionOutcome {
        calls += 1
        let call = calls
        if call == 1 { try await Task.sleep(for: .milliseconds(200)) }
        let fact = ResultFact(id: "result-\(call)", label: "request-\(call)", value: "done", state: .verified, source: "test", observedAt: .now, priority: 1)
        return .result(try DeterministicResultComposer().compose(primaryAnswer: "request-\(call)", facts: [fact]))
    }
}

@Suite("Contacts request lifecycle")
struct ContactsRequestLifecycleTests {
    @Test func uniqueNotFoundAndAmbiguousAreDeterministic() async throws {
        let one = ContactCandidate(identifier: "1", displayName: "Олег", phoneNumbers: ["+380501234567"])
        let unique = LocalContactResolver(authorization: ContactAuthorizationStub(status: .authorized, granted: true), query: SystemContactQuery(store: ContactStoreStub(values: [one])))
        #expect(try await unique.resolve(name: "Олег") == .resolved(one))
        let missing = LocalContactResolver(authorization: ContactAuthorizationStub(status: .limited, granted: true), query: SystemContactQuery(store: ContactStoreStub()))
        #expect(try await missing.resolve(name: "Немає") == .notFound)
        let two = ContactCandidate(identifier: "2", displayName: "Олег Робота", phoneNumbers: ["2"])
        let ambiguous = LocalContactResolver(authorization: ContactAuthorizationStub(status: .authorized, granted: true), query: SystemContactQuery(store: ContactStoreStub(values: [one, two])))
        #expect(try await ambiguous.resolve(name: "Олег") == .ambiguous([one, two]))
    }

    @Test func deniedRestrictedAndFailedGrantReturnTruthfully() async {
        for status in [ContactAuthorizationState.denied, .restricted] {
            let resolver = LocalContactResolver(authorization: ContactAuthorizationStub(status: status, granted: false), query: SystemContactQuery(store: ContactStoreStub()))
            await #expect(throws: ContactResolutionError.permissionDenied) { try await resolver.requestAccessIfNeeded() }
        }
        let pending = LocalContactResolver(authorization: ContactAuthorizationStub(status: .notDetermined, granted: false), query: SystemContactQuery(store: ContactStoreStub()))
        await #expect(throws: ContactResolutionError.permissionDenied) { try await pending.requestAccessIfNeeded() }
    }

    @Test func slowSynchronousStoreTimesOutWithoutWaitingForLateCompletion() async {
        // The late synchronous operation deliberately outlives scheduler pressure
        // from the full parallel suite; the deadline must still win promptly.
        let query = SystemContactQuery(store: ContactStoreStub(delay: 1.5))
        let start = ContinuousClock.now
        await #expect(throws: ContactResolutionError.timedOut) { try await query.contacts(matching: "Олег", timeout: .milliseconds(30)) }
        #expect(start.duration(to: .now) < .seconds(1))
    }

    @Test func cancellationCompletesPromptlyAndLateStoreCannotResumeTwice() async {
        let query = SystemContactQuery(store: ContactStoreStub(delay: 1.5))
        let task = Task { try await query.contacts(matching: "Олег", timeout: .seconds(3)) }
        try? await Task.sleep(for: .milliseconds(20))
        task.cancel()
        await #expect(throws: ContactResolutionError.cancelled) { try await task.value }
        try? await Task.sleep(for: .milliseconds(20))
    }

    @Test func frameworkReferenceErrorIsMappedBeforeCrossingAsyncBoundary() async {
        let query = SystemContactQuery(store: FailingContactStoreStub())
        await #expect(throws: ContactResolutionError.queryFailed) {
            try await query.contacts(matching: "Ірина", timeout: .seconds(1))
        }
    }

    @Test @MainActor func newerHomeRequestOwnsResultAndSpinnerTerminates() async throws {
        let executor = SequencedCapabilityExecutor()
        let model = AssistantViewModel(capabilityExecutor: executor)
        model.input = "Знайди контакт Олег"
        model.submit()
        model.input = "Знайди контакт Сашко"
        model.submit()
        for _ in 0..<100 {
            if case let .deterministic(result) = model.resultState, result.primaryAnswer == "request-2" { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard case let .deterministic(result) = model.resultState else { Issue.record("Expected current deterministic result"); return }
        #expect(result.primaryAnswer == "request-2")
        try await Task.sleep(for: .milliseconds(250))
        guard case let .deterministic(final) = model.resultState else { Issue.record("Late request changed state"); return }
        #expect(final.primaryAnswer == "request-2")
        #expect(model.statusText != AppText.value("processing"))
    }
}
