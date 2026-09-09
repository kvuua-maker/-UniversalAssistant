@preconcurrency import Contacts
import Foundation
import Testing
@testable import UniversalAssistant

@MainActor
private final class ContactsFrameworkOpenCapture {
    private(set) var urls: [URL] = []
    func open(_ url: URL) { urls.append(url) }
}

@Suite("Contacts framework Release integration", .serialized)
@MainActor
struct ContactsFrameworkReleaseIntegrationTests {
    private func wait(
        timeout: Duration = .seconds(5),
        _ predicate: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Release-root Contacts request did not terminate")
    }

    @Test func testOwnedSystemContactResolvesThroughShippedCallAndMessagePaths() async throws {
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
            Issue.record(
                "This framework-boundary test requires full Contacts access for com.universalassistant.app.dev in the selected simulator"
            )
            return
        }

        let store = CNContactStore()
        let contact = CNMutableContact()
        contact.givenName = "Соломія"
        contact.familyName = "Квантова"
        contact.phoneNumbers = [
            CNLabeledValue(
                label: CNLabelPhoneNumberMobile,
                value: CNPhoneNumber(stringValue: "+380 63 418 27 56")
            )
        ]
        let save = CNSaveRequest()
        save.add(contact, toContainerWithIdentifier: nil)
        try store.execute(save)
        defer {
            let cleanup = CNSaveRequest()
            cleanup.delete(contact)
            try? store.execute(cleanup)
        }

        let openCapture = ContactsFrameworkOpenCapture()
        let callModel = ProductionAssistantComposition.makeModel(
            personalSearchSources: [],
            compactResultDuration: .seconds(60),
            systemHandoffOpen: openCapture.open
        )
        callModel.input = "Набери Соломію Квантову телефоном"
        callModel.submit()
        try await wait {
            if case .failure = callModel.resultState { return true }
            return !openCapture.urls.isEmpty
        }

        #expect({ if case .failure = callModel.resultState { return false }; return true }())
        #expect(openCapture.urls.count == 1)
        #expect(openCapture.urls.first?.scheme == "tel")
        #expect(openCapture.urls.first?.absoluteString.contains("wa.me") == false)
        #expect(callModel.statusText != AppText.value("processing"))

        let messageModel = ProductionAssistantComposition.makeModel(
            personalSearchSources: [],
            compactResultDuration: .seconds(60)
        )
        messageModel.input = "Надішли Соломії Квантовій повідомлення про зміну часу"
        messageModel.submit()
        try await wait {
            if case .failure = messageModel.resultState { return true }
            return messageModel.capabilityPresentation != nil
        }

        #expect({ if case .failure = messageModel.resultState { return false }; return true }())
        guard case let .message(recipients, body)? = messageModel.capabilityPresentation else {
            Issue.record("Release-root message did not reach MessageUI presentation")
            return
        }
        #expect(recipients == ["380634182756"])
        #expect(body?.contains("зміну часу") == true)
        #expect(messageModel.statusText != AppText.value("processing"))
    }
}

