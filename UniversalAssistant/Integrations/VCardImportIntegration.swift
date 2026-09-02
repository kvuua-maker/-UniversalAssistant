import Contacts
import ContactsUI

enum VCardImportError: Error, Equatable { case invalidVCard }

@MainActor
struct VCardImportIntegration {
    func makeConfirmationController(data: Data) throws -> CNContactViewController {
        let contacts: [CNContact]
        do { contacts = try CNContactVCardSerialization.contacts(with: data) }
        catch { throw VCardImportError.invalidVCard }
        guard let first = contacts.first else { throw VCardImportError.invalidVCard }
        let mutable = first.mutableCopy() as? CNMutableContact
        guard let mutable else { throw VCardImportError.invalidVCard }
        return CNContactViewController(forNewContact: mutable)
    }
}
