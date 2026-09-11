@preconcurrency import Contacts
import Foundation

struct ContactCandidate: Equatable, Sendable {
    let identifier: String
    let displayName: String
    let phoneNumbers: [String]
    let emailAddresses: [String]
    let aliases: [String]

    init(
        identifier: String,
        displayName: String,
        phoneNumbers: [String],
        emailAddresses: [String] = [],
        aliases: [String] = []
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.phoneNumbers = phoneNumbers
        self.emailAddresses = emailAddresses
        self.aliases = aliases
    }
}
enum ContactResolution: Equatable, Sendable { case resolved(ContactCandidate), ambiguous([ContactCandidate]), notFound }
enum ContactResolutionError: Error, Equatable, Sendable { case permissionRequired, permissionDenied, timedOut, cancelled, queryFailed }

protocol ContactResolving: Sendable {
    func authorizationState() async -> ContactAuthorizationState
    func requestAccessIfNeeded() async throws
    func resolve(name: String) async throws -> ContactResolution
    func resolve(exactIdentifier identifier: String) async throws -> ContactResolution
    func contextualVocabulary(limit: Int) async -> [String]
}
extension ContactResolving {
    func authorizationState() async -> ContactAuthorizationState { .authorized }
    func contextualVocabulary(limit: Int) async -> [String] { [] }
}
protocol ContactQuerying: Sendable {
    func contacts(matching name: String, timeout: Duration) async throws -> [ContactCandidate]
    func contact(identifier: String, timeout: Duration) async throws -> ContactCandidate?
    func accessibleContacts(limit: Int, timeout: Duration) async throws -> [ContactCandidate]
}
extension ContactQuerying {
    func accessibleContacts(limit: Int, timeout: Duration) async throws -> [ContactCandidate] { [] }
}
enum ContactAuthorizationState: Equatable, Sendable { case notDetermined, authorized, limited, denied, restricted }
protocol ContactAuthorizing: Sendable {
    func currentStatus() -> ContactAuthorizationState
    func requestAccess() async throws -> Bool
}
struct SystemContactAuthorization: ContactAuthorizing {
    func currentStatus() -> ContactAuthorizationState {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .limited: .limited
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .restricted
        }
    }
    func requestAccess() async throws -> Bool {
        // Create and use the Contacts object in this invocation. CNContactStore is
        // not Sendable; retaining one in a Sendable boundary and later invoking it
        // on another executor is an avoidable lifetime/thread hazard.
        try await CNContactStore().requestAccess(for: .contacts)
    }
}

protocol ContactStoreQuerying: Sendable {
    func contacts(matching name: String) throws -> [ContactCandidate]
    func contact(identifier: String) throws -> ContactCandidate?
    func accessibleContacts(limit: Int) throws -> [ContactCandidate]
}
extension ContactStoreQuerying {
    func accessibleContacts(limit: Int) throws -> [ContactCandidate] { [] }
}
final class SystemContactStoreQuery: ContactStoreQuerying, Sendable {
    func contacts(matching name: String) throws -> [ContactCandidate] {
        let store = CNContactStore()
        return try store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: name), keysToFetch: Self.keys).map(Self.candidate)
    }
    func contact(identifier: String) throws -> ContactCandidate? {
        let store = CNContactStore()
        do { return Self.candidate(try store.unifiedContact(withIdentifier: identifier, keysToFetch: Self.keys)) }
        catch let error as CNError where error.code == .recordDoesNotExist { return nil }
    }
    func accessibleContacts(limit: Int) throws -> [ContactCandidate] {
        guard limit > 0 else { return [] }
        let request = CNContactFetchRequest(keysToFetch: Self.keys)
        request.sortOrder = .userDefault
        request.unifyResults = true
        request.mutableObjects = false
        var values: [ContactCandidate] = []
        try CNContactStore().enumerateContacts(with: request) { contact, stop in
            values.append(Self.candidate(contact))
            if values.count >= limit { stop.pointee = true }
        }
        return values
    }
    private static let keys: [CNKeyDescriptor] = [
        CNContactIdentifierKey as CNKeyDescriptor,
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactNicknameKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor,
        CNContactRelationsKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor
    ]
    private static func candidate(_ contact: CNContact) -> ContactCandidate {
        let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        let displayName = name.isEmpty ? contact.organizationName : name
        let aliases = [
            displayName, contact.givenName, contact.familyName, contact.nickname,
            contact.organizationName
        ] + contact.contactRelations.map(\.value.name)
        return .init(
            identifier: contact.identifier,
            displayName: displayName,
            phoneNumbers: contact.phoneNumbers.map { $0.value.stringValue },
            emailAddresses: contact.emailAddresses.map { String($0.value) },
            aliases: aliases.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        )
    }
}

private final class ContactQueryCompletion<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?
    func install(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock(); if let result { lock.unlock(); continuation.resume(with: result) } else { self.continuation = continuation; lock.unlock() }
    }
    func finish(_ result: Result<Value, Error>) {
        lock.lock(); guard self.result == nil else { lock.unlock(); return }; self.result = result
        let continuation = self.continuation; self.continuation = nil; lock.unlock(); continuation?.resume(with: result)
    }
}

final class SystemContactQuery: ContactQuerying, @unchecked Sendable {
    private static let deadlineQueue = DispatchQueue(label: "com.universalassistant.contacts.deadline", qos: .userInteractive)
    private let store: any ContactStoreQuerying
    private let queue = DispatchQueue(label: "com.universalassistant.contacts.query", qos: .userInitiated)
    init(store: any ContactStoreQuerying = SystemContactStoreQuery()) { self.store = store }
    func contacts(matching name: String, timeout: Duration) async throws -> [ContactCandidate] {
        try await bounded(timeout: timeout) { [store] in try store.contacts(matching: name) }
    }
    func contact(identifier: String, timeout: Duration) async throws -> ContactCandidate? {
        try await bounded(timeout: timeout) { [store] in try store.contact(identifier: identifier) }
    }
    func accessibleContacts(limit: Int, timeout: Duration) async throws -> [ContactCandidate] {
        try await bounded(timeout: timeout) { [store] in try store.accessibleContacts(limit: limit) }
    }
    private func bounded<Value: Sendable>(timeout: Duration, operation: @escaping @Sendable () throws -> Value) async throws -> Value {
        let completion = ContactQueryCompletion<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                completion.install(continuation)
                queue.async {
                    do { completion.finish(.success(try operation())) }
                    catch is CancellationError { completion.finish(.failure(ContactResolutionError.cancelled)) }
                    // Foundation/Contacts errors are Objective-C reference values.
                    // Do not send them across this concurrency boundary; the Home
                    // layer needs a stable typed failure, not framework internals.
                    catch { completion.finish(.failure(ContactResolutionError.queryFailed)) }
                }
                let components = timeout.components
                let delay = Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
                Self.deadlineQueue.asyncAfter(deadline: .now() + delay) {
                    completion.finish(.failure(ContactResolutionError.timedOut))
                }
            }
        } onCancel: { completion.finish(.failure(ContactResolutionError.cancelled)) }
    }
}

actor LocalContactResolver: ContactResolving {
    private let authorization: any ContactAuthorizing
    private let query: any ContactQuerying
    /// Three seconds is above normal local lookup latency but keeps Home within one interactive turn.
    private let queryTimeout: Duration
    init(authorization: any ContactAuthorizing = SystemContactAuthorization(), query: any ContactQuerying = SystemContactQuery(), queryTimeout: Duration = .seconds(3)) {
        self.authorization = authorization; self.query = query; self.queryTimeout = queryTimeout
    }
    func authorizationState() -> ContactAuthorizationState { authorization.currentStatus() }
    func requestAccessIfNeeded() async throws {
        LocalVoiceDiagnosticReport.shared.record("contacts_authorization_started")
        switch authorization.currentStatus() {
        case .authorized, .limited:
            LocalVoiceDiagnosticReport.shared.record("contacts_authorization_finished", "status=authorized")
            return
        case .notDetermined:
            guard try await authorization.requestAccess() else {
                LocalVoiceDiagnosticReport.shared.record("contacts_authorization_finished", "status=denied")
                throw ContactResolutionError.permissionDenied
            }
            LocalVoiceDiagnosticReport.shared.record("contacts_authorization_finished", "status=authorized")
        case .denied, .restricted:
            LocalVoiceDiagnosticReport.shared.record("contacts_authorization_finished", "status=denied")
            throw ContactResolutionError.permissionDenied
        }
    }
    func resolve(name: String) async throws -> ContactResolution {
        try verifyAuthorization()
        LocalVoiceDiagnosticReport.shared.recordBoundaryPre("CONTACT_FETCH", "kind=name")
        defer { LocalVoiceDiagnosticReport.shared.recordBoundaryPost("CONTACT_FETCH", "kind=name status=returned") }
        LocalVoiceDiagnosticReport.shared.record("contacts_query_started", "kind=name")
        let predicateContacts = try await query.contacts(matching: name, timeout: queryTimeout)
        let predicateEvidence = resolveCandidates(predicateContacts, query: name)
        let result: ContactResolution
        switch predicateEvidence.resolution {
        case .resolved, .ambiguous:
            result = predicateEvidence.resolution
        case .notFound:
            // CNContact's name predicate is a candidate source, not proof of
            // identity. Build 34 proved that blindly accepting its sole fuzzy
            // result can call a different person. Validate against the complete
            // privacy-authorized domain before selecting any person.
            let accessible = try await query.accessibleContacts(limit: 200, timeout: queryTimeout)
            let domainEvidence = resolveCandidates(accessible, query: name)
            result = domainEvidence.resolution
            LocalVoiceDiagnosticReport.shared.record(
                "contacts_domain_recovery_finished",
                "status=\(Self.status(domainEvidence.resolution)) count=\(domainEvidence.candidateCount) mechanism=\(domainEvidence.mechanism.rawValue)"
            )
        }
        LocalVoiceDiagnosticReport.shared.record(
            "contacts_query_finished",
            "status=\(Self.status(result)) count=\(predicateEvidence.candidateCount)"
        )
        return result
    }
    func resolve(exactIdentifier identifier: String) async throws -> ContactResolution {
        try verifyAuthorization()
        LocalVoiceDiagnosticReport.shared.recordBoundaryPre("CONTACT_FETCH", "kind=identifier")
        defer { LocalVoiceDiagnosticReport.shared.recordBoundaryPost("CONTACT_FETCH", "kind=identifier status=returned") }
        LocalVoiceDiagnosticReport.shared.record("contacts_query_started", "kind=identifier")
        guard let value = try await query.contact(identifier: identifier, timeout: queryTimeout) else {
            LocalVoiceDiagnosticReport.shared.record("contacts_query_finished", "status=no_result count=0")
            return .notFound
        }
        LocalVoiceDiagnosticReport.shared.record("contacts_query_finished", "status=success count=1")
        return .resolved(value)
    }
    func contextualVocabulary(limit: Int) async -> [String] {
        guard limit > 0 else { return [] }
        switch authorization.currentStatus() {
        case .authorized, .limited: break
        case .notDetermined, .denied, .restricted: return []
        }
        do {
            let values = try await query.accessibleContacts(limit: min(limit, 100), timeout: .seconds(1))
            let names = values.map(\.displayName).filter { !$0.isEmpty }
            LocalVoiceDiagnosticReport.shared.record("contacts_context_vocabulary", "count=\(names.count)")
            return names
        } catch {
            LocalVoiceDiagnosticReport.shared.record("contacts_context_vocabulary", "count=0 status=unavailable")
            return []
        }
    }
    private func verifyAuthorization() throws {
        switch authorization.currentStatus() {
        case .authorized, .limited: return
        case .notDetermined: throw ContactResolutionError.permissionRequired
        case .denied, .restricted: throw ContactResolutionError.permissionDenied
        }
    }

    private func resolveCandidates(
        _ contacts: [ContactCandidate],
        query name: String
    ) -> (resolution: ContactResolution, mechanism: ScopedEntityMatchMechanism, candidateCount: Int) {
        guard !contacts.isEmpty else { return (.notFound, .unresolved, 0) }
        let domain = contacts.map {
            ScopedEntityCandidate(
                value: $0,
                displayName: $0.displayName,
                aliases: Set([$0.displayName] + $0.aliases)
            )
        }
        let evidence = ContextScopedEntityResolver(candidates: domain).resolveWithEvidence(name)
        switch evidence.resolution {
        case let .resolved(contact):
            return (.resolved(contact), evidence.mechanism, contacts.count)
        case let .ambiguous(names):
            let selected = contacts.filter { names.contains($0.displayName) }
            return (.ambiguous(selected.isEmpty ? contacts : selected), evidence.mechanism, contacts.count)
        case .unresolved:
            return (.notFound, evidence.mechanism, contacts.count)
        }
    }

    private static func status(_ resolution: ContactResolution) -> String {
        switch resolution {
        case .resolved: "resolved"
        case .ambiguous: "ambiguous"
        case .notFound: "no_result"
        }
    }
}
