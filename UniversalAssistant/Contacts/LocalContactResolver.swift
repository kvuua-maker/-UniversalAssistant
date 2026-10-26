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

extension ContactCandidate {
    /// A user-visible discriminator for same-name contacts. The opaque Contacts
    /// identifier remains internal; only existing authorized fields are shown.
    var selectionLabel: String {
        if let phone = phoneNumbers.first {
            let digits = phone.filter(\.isNumber)
            return "\(displayName) · •••\(digits.suffix(4))"
        }
        if let email = emailAddresses.first { return "\(displayName) · \(email)" }
        return displayName
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
    private var result: Result<Value, ContactResolutionError>?
    func install(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock(); if let result { lock.unlock(); continuation.resume(with: result) } else { self.continuation = continuation; lock.unlock() }
    }
    func finish(_ result: Result<Value, ContactResolutionError>) {
        lock.lock(); guard self.result == nil else { lock.unlock(); return }; self.result = result
        let continuation = self.continuation; self.continuation = nil; lock.unlock()
        switch result {
        case let .success(value): continuation?.resume(returning: value)
        case let .failure(error): continuation?.resume(throwing: error)
        }
    }
}

final class SystemContactQuery: ContactQuerying, @unchecked Sendable {
    private static let deadlineQueue = DispatchQueue(label: "com.universalassistant.contacts.deadline", qos: .userInteractive)
    /// Provides an explicit happens-before edge between the blocking Contacts
    /// producer and the actor consuming its owned Swift value.
    private static let resultQueue = DispatchQueue(label: "com.universalassistant.contacts.result", qos: .userInitiated)
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
                    let result: Result<Value, ContactResolutionError>
                    do { result = .success(try operation()) }
                    catch is CancellationError { result = .failure(.cancelled) }
                    // Foundation/Contacts errors are Objective-C reference values.
                    // Do not send them across this concurrency boundary; the Home
                    // layer needs a stable typed failure, not framework internals.
                    catch { result = .failure(.queryFailed) }
                    Self.resultQueue.async { completion.finish(result) }
                }
                let components = timeout.components
                let delay = Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
                Self.deadlineQueue.asyncAfter(deadline: .now() + delay) {
                    Self.resultQueue.async { completion.finish(.failure(.timedOut)) }
                }
            }
        } onCancel: {
            Self.resultQueue.async { completion.finish(.failure(.cancelled)) }
        }
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
        // CNContact's predicate is sufficient when it proves exactly one
        // strong identity. Avoid the expensive full authorized-domain scan in
        // this common path; ambiguity safety remains unchanged below.
        let predicateEvidence = resolveCandidates(predicateContacts, query: name)
        if predicateEvidence.mechanism == .exact,
           case .resolved = predicateEvidence.resolution {
            LocalVoiceDiagnosticReport.shared.record(
                "contacts_query_finished",
                "status=resolved count=1 mechanism=predicate_exact_fast_path"
            )
            return predicateEvidence.resolution
        }
        let accessibleContacts: [ContactCandidate]
        do {
            accessibleContacts = try await query.accessibleContacts(limit: 500, timeout: queryTimeout)
        } catch {
            // A predicate result is safe on its own only when it is exact.
            // Fuzzy evidence from a provider-pruned subset cannot identify a
            // person without comparison against the authorized domain.
            let result = predicateEvidence.mechanism == .exact ? predicateEvidence.resolution : .notFound
            LocalVoiceDiagnosticReport.shared.record(
                "contacts_domain_recovery_finished",
                "status=\(Self.status(result)) count=\(predicateEvidence.candidateCount) mechanism=predicate_only"
            )
            return result
        }
        // CNContact's predicate is a candidate source, not identity proof.
        // Rank the union exactly once so a short unrelated predicate hit cannot
        // win simply because the real contact was excluded from that subset.
        let candidates = Self.deduplicated(predicateContacts + accessibleContacts)
        let domainEvidence = resolveCandidates(candidates, query: name)
        let result = domainEvidence.resolution
        LocalVoiceDiagnosticReport.shared.record(
            "contacts_domain_recovery_finished",
            "status=\(Self.status(result)) count=\(domainEvidence.candidateCount) mechanism=\(domainEvidence.mechanism.rawValue)"
        )
        LocalVoiceDiagnosticReport.shared.record(
            "contacts_query_finished", "status=\(Self.status(result)) count=\(domainEvidence.candidateCount)"
        )
        // Several people can share the spoken name. Even when the scorer prefers
        // one of them, the user must choose: guessing here dials the wrong person.
        if case .resolved = result, domainEvidence.candidateCount > 1 {
            let lowered = name.lowercased()
            let sameName = candidates.filter { candidate in
                candidate.displayName.lowercased().split(separator: " ").contains { word in
                    word.hasPrefix(lowered) || lowered.hasPrefix(String(word))
                }
            }
            if sameName.count > 1 {
                LocalVoiceDiagnosticReport.shared.record(
                    "contacts_query_ambiguous", "count=\(sameName.count)"
                )
                return .ambiguous(sameName)
            }
        }
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
            var seen: Set<String> = []
            let names = values.flatMap { [$0.displayName] + $0.aliases }.filter { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return false }
                return seen.insert(CanonicalMorphology.comparableText(trimmed)).inserted
            }.prefix(limit)
            LocalVoiceDiagnosticReport.shared.record("contacts_context_vocabulary", "count=\(names.count)")
            return Array(names)
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
        let comparableQuery = CanonicalMorphology.comparableText(name)
        let exact = contacts.filter { contact in
            ([contact.displayName] + contact.aliases).contains {
                CanonicalMorphology.comparableText($0) == comparableQuery
            }
        }
        if exact.count == 1, let value = exact.first {
            return (.resolved(value), .exact, contacts.count)
        }
        if exact.count > 1 {
            return (.ambiguous(Self.deduplicated(exact)), .exact, contacts.count)
        }
        let domain = contacts.filter { contact in
            let identityValues = [contact.displayName] + contact.aliases
            return identityValues.contains { value in
                let comparable = CanonicalMorphology.comparableText(value)
                guard comparable.count >= 3, comparableQuery.count >= 2 else { return false }
                return comparable.contains(comparableQuery) || comparableQuery.contains(comparable) ||
                    Self.sharesMorphologyEvidence(name, value)
            }
        }.map {
            ScopedEntityCandidate(
                value: $0,
                displayName: $0.displayName,
                aliases: Set([$0.displayName] + $0.aliases)
            )
        }
        guard !domain.isEmpty else { return (.notFound, .unresolved, contacts.count) }
        let resolver = ContextScopedEntityResolver(
            candidates: domain,
            directThreshold: 0.90,
            ambiguityThreshold: 0.60,
            requiredMargin: 0.18
        )
        let tokens = name.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        var subjects = [name]
        if tokens.count > 1 {
            for length in 1...min(4, tokens.count) {
                for start in 0...(tokens.count - length) {
                    subjects.append(tokens[start..<(start + length)].joined(separator: " "))
                }
            }
        }
        let evidence = subjects.map(resolver.resolveWithEvidence).max {
            if $0.bestScore == $1.bestScore { return $0.confidenceMargin < $1.confidenceMargin }
            return $0.bestScore < $1.bestScore
        } ?? resolver.resolveWithEvidence(name)
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

    private static func deduplicated(_ contacts: [ContactCandidate]) -> [ContactCandidate] {
        var values: [String: ContactCandidate] = [:]
        for contact in contacts {
            values[contact.identifier] = contact
        }
        return values.values.sorted {
            $0.displayName == $1.displayName ? $0.identifier < $1.identifier : $0.displayName < $1.displayName
        }
    }

    private static func sharesMorphologyEvidence(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let right = rhs.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard !left.isEmpty, !right.isEmpty else { return false }
        let intersections = left.reduce(into: 0) { count, token in
            let forms = CanonicalMorphology.forms(for: token).filter { $0.count >= 3 }
            if right.contains(where: { !forms.isDisjoint(with: CanonicalMorphology.forms(for: $0)) }) {
                count += 1
            }
        }
        // A multi-token identity needs more than an accidental one-token hit;
        // a single-name lookup may legitimately match one contact-name token.
        return intersections >= (min(left.count, right.count) > 1 ? 2 : 1)
    }

    private static func status(_ resolution: ContactResolution) -> String {
        switch resolution {
        case .resolved: "resolved"
        case .ambiguous: "ambiguous"
        case .notFound: "no_result"
        }
    }
}
