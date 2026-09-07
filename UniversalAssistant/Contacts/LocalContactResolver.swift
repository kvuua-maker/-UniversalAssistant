@preconcurrency import Contacts
import Foundation

struct ContactCandidate: Equatable, Sendable { let identifier: String; let displayName: String; let phoneNumbers: [String] }
enum ContactResolution: Equatable, Sendable { case resolved(ContactCandidate), ambiguous([ContactCandidate]), notFound }
enum ContactResolutionError: Error, Equatable { case permissionRequired, permissionDenied, timedOut, cancelled }

protocol ContactResolving: Sendable {
    func requestAccessIfNeeded() async throws
    func resolve(name: String) async throws -> ContactResolution
    func resolve(exactIdentifier identifier: String) async throws -> ContactResolution
}
protocol ContactQuerying: Sendable {
    func contacts(matching name: String, timeout: Duration) async throws -> [ContactCandidate]
    func contact(identifier: String, timeout: Duration) async throws -> ContactCandidate?
}
enum ContactAuthorizationState: Equatable, Sendable { case notDetermined, authorized, limited, denied, restricted }
protocol ContactAuthorizing: Sendable {
    func currentStatus() -> ContactAuthorizationState
    func requestAccess() async throws -> Bool
}
struct SystemContactAuthorization: ContactAuthorizing {
    private let store: CNContactStore
    init(store: CNContactStore = CNContactStore()) { self.store = store }
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
    func requestAccess() async throws -> Bool { try await store.requestAccess(for: .contacts) }
}

protocol ContactStoreQuerying: Sendable {
    func contacts(matching name: String) throws -> [ContactCandidate]
    func contact(identifier: String) throws -> ContactCandidate?
}
final class SystemContactStoreQuery: ContactStoreQuerying, @unchecked Sendable {
    private let store: CNContactStore
    init(store: CNContactStore = CNContactStore()) { self.store = store }
    func contacts(matching name: String) throws -> [ContactCandidate] {
        try store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: name), keysToFetch: Self.keys).map(Self.candidate)
    }
    func contact(identifier: String) throws -> ContactCandidate? {
        do { return Self.candidate(try store.unifiedContact(withIdentifier: identifier, keysToFetch: Self.keys)) }
        catch let error as CNError where error.code == .recordDoesNotExist { return nil }
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
    private let store: any ContactStoreQuerying
    private let queue = DispatchQueue(label: "com.universalassistant.contacts.query", qos: .userInitiated)
    init(store: any ContactStoreQuerying = SystemContactStoreQuery()) { self.store = store }
    func contacts(matching name: String, timeout: Duration) async throws -> [ContactCandidate] {
        try await bounded(timeout: timeout) { [store] in try store.contacts(matching: name) }
    }
    func contact(identifier: String, timeout: Duration) async throws -> ContactCandidate? {
        try await bounded(timeout: timeout) { [store] in try store.contact(identifier: identifier) }
    }
    private func bounded<Value: Sendable>(timeout: Duration, operation: @escaping @Sendable () throws -> Value) async throws -> Value {
        let completion = ContactQueryCompletion<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                completion.install(continuation)
                queue.async { do { completion.finish(.success(try operation())) } catch { completion.finish(.failure(error)) } }
                let components = timeout.components
                let delay = Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) {
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
    func requestAccessIfNeeded() async throws {
        switch authorization.currentStatus() {
        case .authorized, .limited: return
        case .notDetermined: guard try await authorization.requestAccess() else { throw ContactResolutionError.permissionDenied }
        case .denied, .restricted: throw ContactResolutionError.permissionDenied
        }
    }
    func resolve(name: String) async throws -> ContactResolution {
        try verifyAuthorization()
        let contacts = try await query.contacts(matching: name, timeout: queryTimeout)
        if contacts.isEmpty { return .notFound }; if contacts.count == 1 { return .resolved(contacts[0]) }; return .ambiguous(contacts)
    }
    func resolve(exactIdentifier identifier: String) async throws -> ContactResolution {
        try verifyAuthorization(); guard let value = try await query.contact(identifier: identifier, timeout: queryTimeout) else { return .notFound }; return .resolved(value)
    }
    private func verifyAuthorization() throws {
        switch authorization.currentStatus() {
        case .authorized, .limited: return
        case .notDetermined: throw ContactResolutionError.permissionRequired
        case .denied, .restricted: throw ContactResolutionError.permissionDenied
        }
    }
}
