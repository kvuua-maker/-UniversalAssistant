@preconcurrency import Contacts
import Foundation

struct ContactCandidate: Equatable, Sendable { let identifier: String; let displayName: String; let phoneNumbers: [String] }
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
        let store = CNContactStore()
        let request = CNContactFetchRequest(keysToFetch: Self.keys)
        request.sortOrder = .userDefault
        request.unifyResults = true
        request.mutableObjects = false
        var values: [ContactCandidate] = []
        try store.enumerateContacts(with: request) { contact, stop in
            values.append(Self.candidate(contact))
            if values.count >= limit { stop.pointee = true }
        }
        return values.filter { !$0.displayName.isEmpty }
    }
    private static let keys: [CNKeyDescriptor] = [CNContactIdentifierKey as CNKeyDescriptor, CNContactGivenNameKey as CNKeyDescriptor, CNContactFamilyNameKey as CNKeyDescriptor, CNContactOrganizationNameKey as CNKeyDescriptor, CNContactPhoneNumbersKey as CNKeyDescriptor]
    private static func candidate(_ contact: CNContact) -> ContactCandidate {
        let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        return .init(identifier: contact.identifier, displayName: name.isEmpty ? contact.organizationName : name, phoneNumbers: contact.phoneNumbers.map { $0.value.stringValue })
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
    func contextualVocabulary(limit: Int) async -> [String] {
        guard limit > 0, [.authorized, .limited].contains(authorization.currentStatus()) else { return [] }
        do {
            let contacts = try await query.accessibleContacts(limit: limit, timeout: .seconds(1))
            LocalVoiceDiagnosticReport.shared.record("contacts_context_vocabulary", "count=\(contacts.count)")
            return contacts.map(\.displayName)
        } catch {
            LocalVoiceDiagnosticReport.shared.record("contacts_context_vocabulary", "count=0 status=unavailable")
            return []
        }
    }
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
        LocalVoiceDiagnosticReport.shared.record("contacts_query_started", "kind=name")
        var contacts = try await query.contacts(matching: name, timeout: queryTimeout)
        if contacts.isEmpty {
            // The system name predicate is intentionally conservative and may
            // return no rows for an inflected or mildly corrupted transcript.
            // Resolve only inside the privacy-authorized Contacts domain; never
            // invent a person or search the web.
            let accessible = try await query.accessibleContacts(limit: 200, timeout: queryTimeout)
            let domain = accessible.map {
                ScopedEntityCandidate(value: $0, displayName: $0.displayName, aliases: [$0.displayName])
            }
            switch ContextScopedEntityResolver(candidates: domain).resolve(name) {
            case let .resolved(contact): contacts = [contact]
            case let .ambiguous(names): contacts = accessible.filter { names.contains($0.displayName) }
            case .unresolved: break
            }
        }
        let result: ContactResolution
        if contacts.isEmpty { result = .notFound }
        else if contacts.count == 1 { result = .resolved(contacts[0]) }
        else {
            let domain = contacts.map { ScopedEntityCandidate(value: $0, displayName: $0.displayName, aliases: [$0.displayName]) }
            switch ContextScopedEntityResolver(candidates: domain).resolve(name) {
            case let .resolved(contact): result = .resolved(contact)
            case let .ambiguous(names):
                let selected = contacts.filter { names.contains($0.displayName) }
                result = .ambiguous(selected.isEmpty ? contacts : selected)
            case .unresolved:
                // Contacts supplied every candidate in this set; an unsafe fuzzy
                // winner remains a real ambiguity rather than becoming no-result.
                result = .ambiguous(contacts)
            }
        }
        LocalVoiceDiagnosticReport.shared.record("contacts_query_finished", "status=success count=\(contacts.count)")
        return result
    }
    func resolve(exactIdentifier identifier: String) async throws -> ContactResolution {
        try verifyAuthorization()
        LocalVoiceDiagnosticReport.shared.record("contacts_query_started", "kind=identifier")
        guard let value = try await query.contact(identifier: identifier, timeout: queryTimeout) else {
            LocalVoiceDiagnosticReport.shared.record("contacts_query_finished", "status=no_result count=0")
            return .notFound
        }
        LocalVoiceDiagnosticReport.shared.record("contacts_query_finished", "status=success count=1")
        return .resolved(value)
    }
    private func verifyAuthorization() throws {
        switch authorization.currentStatus() {
        case .authorized, .limited: return
        case .notDetermined: throw ContactResolutionError.permissionRequired
        case .denied, .restricted: throw ContactResolutionError.permissionDenied
        }
    }
}
