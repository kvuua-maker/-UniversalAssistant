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

@MainActor
private final class ContactHandoffCapture {
    private(set) var destinations: [URL] = []
    func open(_ url: URL) { destinations.append(url) }
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
        guard case let .presentation(.contactCard(identifier)) = try await executor.execute(resumed) else {
            Issue.record("Expected selected limited contact system card"); return
        }
        #expect(identifier == contact.identifier)
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
        do {
            _ = try await ambiguous.execute(LocalCommandEngine().parse("Покажи контакт Ірини"))
            Issue.record("Expected contact disambiguation")
        } catch let CanonicalCapabilityExecutionError.ambiguousContacts(values) {
            #expect(Set(values.map(\.identifier)) == ["a", "b"])
        } catch { Issue.record("Unexpected error: \(error)") }
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

    @Test func authorizedContactDomainRecoversInflectionAfterSystemNameMiss() async throws {
        let target = ContactCandidate(
            identifier: "contact-km",
            displayName: "Катерина Мельник",
            phoneNumbers: ["+380671234567"]
        )
        let store = ContactDomainStoreStub(accessibleValues: [target])
        let resolver = LocalContactResolver(
            authorization: ContactAuthorizationStub(status: .authorized, granted: true),
            query: SystemContactQuery(store: store)
        )
        #expect(try await resolver.resolve(name: "Катерині Мельник") == .resolved(target))
        #expect(await resolver.contextualVocabulary(limit: 4) == ["Катерина Мельник"])
    }

    @Test func contactVocabularyHonorsPrivacyStateAndBound() async {
        let values = [
            ContactCandidate(identifier: "1", displayName: "Леся Дорош", phoneNumbers: []),
            ContactCandidate(identifier: "2", displayName: "Тарас Коваль", phoneNumbers: [])
        ]
        let query = SystemContactQuery(store: ContactDomainStoreStub(accessibleValues: values))
        let limited = LocalContactResolver(
            authorization: ContactAuthorizationStub(status: .limited, granted: true), query: query
        )
        #expect(await limited.contextualVocabulary(limit: 1) == ["Леся Дорош"])
        let denied = LocalContactResolver(
            authorization: ContactAuthorizationStub(status: .denied, granted: false), query: query
        )
        #expect(await denied.contextualVocabulary(limit: 10).isEmpty)
    }

    @Test func systemPredicateCandidateIsValidatedBeforeItCanSelectAContact() async throws {
        let wrongPredicateCandidate = ContactCandidate(
            identifier: "wrong",
            displayName: "Лідія Савчук",
            phoneNumbers: ["+380501110000"]
        )
        let intended = ContactCandidate(
            identifier: "intended",
            displayName: "Дарина Романюк",
            phoneNumbers: ["+380502220000"],
            emailAddresses: ["daryna@example.org"],
            aliases: ["Дарина", "колега Дарина"]
        )
        let store = ContactDomainStoreStub(
            matchingValues: [wrongPredicateCandidate],
            accessibleValues: [wrongPredicateCandidate, intended]
        )
        let resolver = LocalContactResolver(
            authorization: ContactAuthorizationStub(status: .authorized, granted: true),
            query: SystemContactQuery(store: store)
        )

        #expect(try await resolver.resolve(name: "Дарині Романюк") == .resolved(intended))
        #expect(try await resolver.resolve(name: "колега Дарина") == .resolved(intended))
    }

    @Test func weakUniqueSystemPredicateCandidateFailsClosedInsteadOfSelectingAnotherPerson() async throws {
        let unrelated = ContactCandidate(
            identifier: "unrelated",
            displayName: "Мирослав Черниш",
            phoneNumbers: ["+380673330000"]
        )
        let store = ContactDomainStoreStub(
            matchingValues: [unrelated],
            accessibleValues: [unrelated]
        )
        let resolver = LocalContactResolver(
            authorization: ContactAuthorizationStub(status: .authorized, granted: true),
            query: SystemContactQuery(store: store)
        )
        #expect(try await resolver.resolve(name: "Надії Левченко") == .notFound)
    }

    @Test func selectedCommunicationTargetIsDiagnosedOnlyByStableFingerprint() async throws {
        let privateNumber = "+380991234567"
        let executor = ProductionCanonicalCapabilityExecutor(personalSearchSources: [])
        LocalVoiceDiagnosticReport.shared.reset()

        let command = StructuredCommand(
            originalText: "Зателефонуй за вказаним номером",
            normalizedText: "зателефонуй за вказаним номером",
            language: .uk,
            intent: .contactCall,
            entities: ["phone_number": privateNumber]
        )
        guard case .handoff = try await executor.execute(command) else {
            Issue.record("Expected legitimate telephone handoff")
            return
        }

        let diagnostics = LocalVoiceDiagnosticReport.shared.snapshot()
        #expect(diagnostics.contains("contact_target_selected"))
        #expect(diagnostics.contains("contact_identifier_hash="))
        #expect(diagnostics.contains("service=telephone"))
        #expect(!diagnostics.contains(privateNumber))
    }

    @Test @MainActor func telephoneNumberSelectionResumesOwnedReleaseRequestAndStaleChoiceIsIgnored() async throws {
        let contact = ContactCandidate(
            identifier: "multi-phone",
            displayName: "Дарина Романюк",
            phoneNumbers: ["+380501112233", "+380672223344"]
        )
        let resolver = LimitedContactResolverStub(state: .authorized, named: .resolved(contact))
        let capture = ContactHandoffCapture()
        let model = ProductionAssistantComposition.makeModel(
            contacts: resolver,
            personalSearchSources: [],
            compactResultDuration: .seconds(60),
            systemHandoffOpen: capture.open
        )
        model.input = "Зателефонуй Дарині Романюк"
        model.submit()
        for _ in 0..<200 {
            if case .actionRequired = model.resultState { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard case .actionRequired = model.resultState else {
            Issue.record("Expected typed telephone-number choice")
            return
        }
        model.resolveActionRequiredChoice("+380672223344")
        for _ in 0..<200 where capture.destinations.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(capture.destinations.first?.absoluteString == "tel:+380672223344")

        model.input = "Покажи заряд батареї"
        model.submit()
        let countAfterSupersedingRequest = capture.destinations.count
        model.resolveActionRequiredChoice("+380501112233")
        try await Task.sleep(for: .milliseconds(30))
        #expect(capture.destinations.count == countAfterSupersedingRequest)
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

private final class ContactDomainStoreStub: ContactStoreQuerying, @unchecked Sendable {
    let matchingValues: [ContactCandidate]
    let accessibleValues: [ContactCandidate]
    init(matchingValues: [ContactCandidate] = [], accessibleValues: [ContactCandidate]) {
        self.matchingValues = matchingValues
        self.accessibleValues = accessibleValues
    }
    func contacts(matching name: String) throws -> [ContactCandidate] { matchingValues }
    func contact(identifier: String) throws -> ContactCandidate? {
        accessibleValues.first { $0.identifier == identifier }
    }
    func accessibleContacts(limit: Int) throws -> [ContactCandidate] {
        Array(accessibleValues.prefix(max(0, limit)))
    }
}
