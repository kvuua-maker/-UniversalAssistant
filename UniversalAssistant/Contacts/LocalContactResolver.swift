import Contacts
import Foundation

struct ContactCandidate: Equatable, Sendable {
    let identifier: String
    let displayName: String
    let phoneNumbers: [String]
}

enum ContactResolution: Equatable, Sendable {
    case resolved(ContactCandidate)
    case ambiguous([ContactCandidate])
    case notFound
}

enum ContactResolutionError: Error, Equatable {
    case permissionRequired
    case permissionDenied
}

actor LocalContactResolver {
    private let store = CNContactStore()

    func requestAccessIfNeeded() async throws {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited:
            return
        case .notDetermined:
            let granted = try await store.requestAccess(for: .contacts)
            if !granted { throw ContactResolutionError.permissionDenied }
        case .denied, .restricted:
            throw ContactResolutionError.permissionDenied
        @unknown default:
            throw ContactResolutionError.permissionDenied
        }
    }

    func resolve(name: String) throws -> ContactResolution {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited: break
        case .notDetermined: throw ContactResolutionError.permissionRequired
        case .denied, .restricted: throw ContactResolutionError.permissionDenied
        @unknown default: throw ContactResolutionError.permissionDenied
        }
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]
        let contacts = try store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: name), keysToFetch: keys)
            .map(Self.candidate)
        if contacts.isEmpty { return .notFound }
        if contacts.count == 1 { return .resolved(contacts[0]) }
        return .ambiguous(contacts)
    }

    func resolve(exactIdentifier identifier: String) throws -> ContactResolution {
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]
        do {
            return .resolved(Self.candidate(try store.unifiedContact(withIdentifier: identifier, keysToFetch: keys)))
        } catch let error as CNError where error.code == .recordDoesNotExist {
            return .notFound
        }
    }

    private static func candidate(_ contact: CNContact) -> ContactCandidate {
        let personName = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        return ContactCandidate(
            identifier: contact.identifier,
            displayName: personName.isEmpty ? contact.organizationName : personName,
            phoneNumbers: contact.phoneNumbers.map { $0.value.stringValue }
        )
    }
}
