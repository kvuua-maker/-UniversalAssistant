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


private actor LimitedContactResolverStub: ContactResolving {
    let state: ContactAuthorizationState
    let named: ContactResolution
    let identifiers: [String: ContactResolution]
    private(set) var requestedAccess = 0
    private(set) var resolvedIdentifiers: [String] = []
    init(state: ContactAuthorizationState, named: ContactResolution = .notFound, identifiers: [String: ContactResolution] = [:]) {
        self.state = state; self.named = named; self.identifiers = identifiers
    }
    func authorizationState() async -> ContactAuthorizationState { state }
    func requestAccessIfNeeded() async throws {
        requestedAccess += 1
        if state == .denied || state == .restricted { throw ContactResolutionError.permissionDenied }
    }
    func resolve(name: String) async throws -> ContactResolution { named }
    func resolve(exactIdentifier identifier: String) async throws -> ContactResolution {
        resolvedIdentifiers.append(identifier)
        return identifiers[identifier] ?? .notFound
    }
}


@MainActor
private final class ContactAccessContinuationExecutor: CanonicalCapabilityExecuting {
    private(set) var commands: [StructuredCommand] = []
    func execute(_ command: StructuredCommand) async throws -> CapabilityExecutionOutcome {
        commands.append(command)
        if command.entities["contact_identifier"] == nil {
            return .presentation(.contactAccess(query: command.entities["contact"] ?? "", command: command))
        }
        let fact = ResultFact(id: "contact", label: "Контакт", value: "Доступ надано", state: .verified, source: "Contacts", observedAt: .now, priority: 100)
        return .result(try DeterministicResultComposer().compose(primaryAnswer: "Контакт знайдено", facts: [fact]))
    }
}

@Suite("Contacts request lifecycle")
@MainActor
struct ContactsRequestLifecycleTests {
    @Test func limitedAccessUsesPublicPickerThenExactSelectedIdentifier() async throws {
        let contact = ContactCandidate(identifier: "contact-42", displayName: "Марія Коваль", phoneNumbers: ["+380931112233"])
        let resolver = LimitedContactResolverStub(state: .limited, identifiers: [contact.identifier: .resolved(contact)])
        let executor = ProductionCanonicalCapabilityExecutor(contacts: resolver, personalSearchSources: [])
        let command = LocalCommandEngine().parse("Знайди контакт Марії Коваль")
        guard case let .presentation(.contactAccess(query, suspended)) = try await executor.execute(command) else {
            Issue.record("Expected public limited-contact access continuation"); return
        }
        #expect(!query.isEmpty)
        var entities = suspended.entities
        entities["contact_identifier"] = contact.identifier
        let resumed = StructuredCommand(id: suspended.id, originalText: suspended.originalText, normalizedText: suspended.normalizedText,
                                        language: suspended.language, intent: suspended.intent, entities: entities,
                                        constraints: suspended.constraints, risk: suspended.risk, needsClarification: false)
        guard case let .result(result) = try await executor.execute(resumed) else {
            Issue.record("Expected selected limited contact result"); return
        }
        #expect(result.facts.first?.label == "Марія Коваль")
        #expect(await resolver.resolvedIdentifiers == [contact.identifier])
    }

    @Test func permissionStatesAndAmbiguityTerminateWithoutWebOrFabrication() async throws {
        for state in [ContactAuthorizationState.denied, .restricted] {
            let executor = ProductionCanonicalCapabilityExecutor(contacts: LimitedContactResolverStub(state: state), personalSearchSources: [])
            await #expect(throws: ContactResolutionError.permissionDenied) {
                try await executor.execute(LocalCommandEngine().parse("Покажи контакт Катерини Бондар"))
            }
        }
        let pending = LimitedContactResolverStub(state: .notDetermined, named: .notFound)
        let pendingExecutor = ProductionCanonicalCapabilityExecutor(contacts: pending, personalSearchSources: [])
        await #expect(throws: CanonicalCapabilityExecutionError.unavailable("contact_not_found")) {
            try await pendingExecutor.execute(LocalCommandEngine().parse("Знайди контакт Івана Левченка"))
        }
        #expect(await pending.requestedAccess == 1)
        let choices = [
            ContactCandidate(identifier: "a", displayName: "Ірина Сервіс", phoneNumbers: ["1111111"]),
            ContactCandidate(identifier: "b", displayName: "Ірина Склад", phoneNumbers: ["2222222"])
        ]
        let ambiguous = ProductionCanonicalCapabilityExecutor(contacts: LimitedContactResolverStub(state: .authorized, named: .ambiguous(choices)), personalSearchSources: [])
        await #expect(throws: CanonicalCapabilityExecutionError.ambiguous(["Ірина Сервіс", "Ірина Склад"])) {
            try await ambiguous.execute(LocalCommandEngine().parse("Покажи контакт Ірини"))
        }
    }

    @Test @MainActor func pickerResumeIsGenerationOwnedAndEmptySelectionIsTerminal() async throws {
        let executor = ContactAccessContinuationExecutor()
        let model = AssistantViewModel(capabilityExecutor: executor, compactResultDuration: .seconds(60))
        model.input = "Знайди контакт Наталії Черненко"; model.submit()
        for _ in 0..<100 where model.capabilityPresentation == nil { try await Task.sleep(for: .milliseconds(10)) }
        guard case let .contactAccess(_, suspended)? = model.capabilityPresentation else { Issue.record("Expected contact access UI"); return }
        model.handleContactAccessGranted(["selected-contact"], for: suspended)
        for _ in 0..<100 where executor.commands.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(executor.commands.last?.entities["contact_identifier"] == "selected-contact")
        #expect(model.statusText != AppText.value("processing"))

        let staleExecutor = ContactAccessContinuationExecutor()
        let staleModel = AssistantViewModel(capabilityExecutor: staleExecutor, compactResultDuration: .seconds(60))
        staleModel.input = "Знайди контакт Романа Поліщука"; staleModel.submit()
        for _ in 0..<100 where staleModel.capabilityPresentation == nil { try await Task.sleep(for: .milliseconds(10)) }
        guard case let .contactAccess(_, staleCommand)? = staleModel.capabilityPresentation else { Issue.record("Expected stale picker setup"); return }
        staleModel.input = "Відкрий камеру"; staleModel.submit()
        for _ in 0..<100 where staleExecutor.commands.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        let countAfterNewRequest = staleExecutor.commands.count
        staleModel.handleContactAccessGranted(["obsolete-contact"], for: staleCommand)
        try await Task.sleep(for: .milliseconds(30))
        #expect(staleExecutor.commands.count == countAfterNewRequest)
        #expect(staleExecutor.commands.last?.entities["contact_identifier"] == nil)

        let emptyExecutor = ContactAccessContinuationExecutor()
        let emptyModel = AssistantViewModel(capabilityExecutor: emptyExecutor)
        emptyModel.input = "Покажи контакт Павла Дорошенка"; emptyModel.submit()
        for _ in 0..<100 where emptyModel.capabilityPresentation == nil { try await Task.sleep(for: .milliseconds(10)) }
        guard case let .contactAccess(_, emptyCommand)? = emptyModel.capabilityPresentation else { Issue.record("Expected empty picker setup"); return }
        emptyModel.handleContactAccessGranted([], for: emptyCommand)
        #expect(emptyExecutor.commands.count == 1)
        #expect(emptyModel.statusText != AppText.value("processing"))
    }

    @Test func uniqueNotFoundAndAmbiguousAreDeterministic() async throws {
        let one = ContactCandidate(identifier: "1", displayName: "Олег", phoneNumbers: ["+380501234567"])
        let unique = LocalContactResolver(authorization: ContactAuthorizationStub(status: .authorized, granted: true), query: SystemContactQuery(store: ContactStoreStub(values: [one])))
        #expect(try await unique.resolve(name: "Олег") == .resolved(one))
        let missing = LocalContactResolver(authorization: ContactAuthorizationStub(status: .limited, granted: true), query: SystemContactQuery(store: ContactStoreStub()))
        #expect(try await missing.resolve(name: "Немає") == .notFound)
        let two = ContactCandidate(identifier: "2", displayName: "Олег Робота", phoneNumbers: ["2"])
        let ambiguous = LocalContactResolver(authorization: ContactAuthorizationStub(status: .authorized, granted: true), query: SystemContactQuery(store: ContactStoreStub(values: [one, two])))
        #expect(try await ambiguous.resolve(name: "Олег") == .resolved(one))
        let duplicate = ContactCandidate(identifier: "3", displayName: "Олег", phoneNumbers: ["3"])
        let trueAmbiguity = LocalContactResolver(authorization: ContactAuthorizationStub(status: .authorized, granted: true), query: SystemContactQuery(store: ContactStoreStub(values: [one, duplicate])))
        #expect(try await trueAmbiguity.resolve(name: "Олег") == .ambiguous([one, duplicate]))
    }

    @Test func deniedRestrictedAndFailedGrantReturnTruthfully() async {
        for status in [ContactAuthorizationState.denied, .restricted] {
            let resolver = LocalContactResolver(authorization: ContactAuthorizationStub(status: status, granted: false), query: SystemContactQuery(store: ContactStoreStub()))
            await #expect(throws: ContactResolutionError.permissionDenied) { try await resolver.requestAccessIfNeeded() }
        }
        let pending = LocalContactResolver(authorization: ContactAuthorizationStub(status: .notDetermined, granted: false), query: SystemContactQuery(store: ContactStoreStub()))
        await #expect(throws: ContactResolutionError.permissionDenied) { try await pending.requestAccessIfNeeded() }
    }

    @Test nonisolated func slowSynchronousStoreTimesOutWithoutWaitingForLateCompletion() async {
        // The late synchronous operation deliberately outlives scheduler pressure
        // from the full parallel suite; the deadline must still win promptly.
        let query = SystemContactQuery(store: ContactStoreStub(delay: 4))
        let start = ContinuousClock.now
        await #expect(throws: ContactResolutionError.timedOut) { try await query.contacts(matching: "Олег", timeout: .milliseconds(30)) }
        #expect(start.duration(to: .now) < .seconds(3))
    }

    @Test nonisolated func cancellationCompletesPromptlyAndLateStoreCannotResumeTwice() async {
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
