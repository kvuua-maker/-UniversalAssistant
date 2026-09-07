import Foundation
import Testing
@testable import UniversalAssistant

private actor CallContactResolverStub: ContactResolving {
    let resolution: ContactResolution
    init(_ resolution: ContactResolution) { self.resolution = resolution }
    func requestAccessIfNeeded() async throws {}
    func resolve(name: String) async throws -> ContactResolution { resolution }
    func resolve(exactIdentifier identifier: String) async throws -> ContactResolution { resolution }
}

@Suite("Production telephone routing")
@MainActor
struct ProductionCallRoutingTests {
    @Test func semanticCallVariantsConverge() {
        let parser = LocalCommandEngine()
        for phrase in ["Подзвони мамі", "Набери маму", "Зателефонуй мамі", "Позвони маме", "Dial Mum"] {
            #expect(parser.parse(phrase).intent == .contactCall)
        }
    }

    @Test func normalContactCallProducesOnlyPublicTelephoneHandoff() async throws {
        let contact = ContactCandidate(identifier: "mother", displayName: "Мама", phoneNumbers: ["+380 50 123 45 67"])
        let executor = ProductionCanonicalCapabilityExecutor(contacts: CallContactResolverStub(.resolved(contact)), personalSearchSources: [])
        let command = LocalCommandEngine().parse("Подзвони мамі")
        guard case let .handoff(result) = try await executor.execute(command) else { Issue.record("Expected telephone handoff"); return }
        #expect(result.destination.absoluteString == "tel:+380501234567")
        #expect(result.destination.scheme == "tel")
    }

    @Test func explicitWhatsAppIsSeparateAndNeverSelectedImplicitly() async throws {
        let contact = ContactCandidate(identifier: "mother", displayName: "Мама", phoneNumbers: ["+380 50 123 45 67"])
        let executor = ProductionCanonicalCapabilityExecutor(contacts: CallContactResolverStub(.resolved(contact)), personalSearchSources: [])
        let normal = try await executor.execute(LocalCommandEngine().parse("Набери маму"))
        let explicit = try await executor.execute(LocalCommandEngine().parse("Подзвони мамі у WhatsApp"))
        guard case let .handoff(normalResult) = normal, case let .handoff(explicitResult) = explicit else { Issue.record("Expected handoffs"); return }
        #expect(normalResult.destination.scheme == "tel")
        #expect(explicitResult.destination.absoluteString == "https://wa.me/380501234567")
    }

    @Test func directNumberDoesNotRequireContacts() async throws {
        let executor = ProductionCanonicalCapabilityExecutor(contacts: CallContactResolverStub(.notFound), personalSearchSources: [])
        let command = LocalCommandEngine().parse("Зателефонуй на номер 123456789")
        #expect(command.entities["phone_number"] == "123456789")
        guard case let .handoff(result) = try await executor.execute(command) else { Issue.record("Expected direct telephone handoff"); return }
        #expect(result.destination.absoluteString == "tel:123456789")
    }

    @Test func multipleNumbersAndAmbiguousContactsRequireChoice() async {
        let multiple = ContactCandidate(identifier: "mother", displayName: "Мама", phoneNumbers: ["1111111", "2222222"])
        let executor = ProductionCanonicalCapabilityExecutor(contacts: CallContactResolverStub(.resolved(multiple)), personalSearchSources: [])
        await #expect(throws: CanonicalCapabilityExecutionError.ambiguous(["1111111", "2222222"])) { try await executor.execute(LocalCommandEngine().parse("Подзвони мамі")) }
        let choices = [ContactCandidate(identifier: "1", displayName: "Олег", phoneNumbers: ["1111111"]), .init(identifier: "2", displayName: "Олег Робота", phoneNumbers: ["2222222"])]
        let ambiguous = ProductionCanonicalCapabilityExecutor(contacts: CallContactResolverStub(.ambiguous(choices)), personalSearchSources: [])
        await #expect(throws: CanonicalCapabilityExecutionError.ambiguous(["Олег", "Олег Робота"])) { try await ambiguous.execute(LocalCommandEngine().parse("Подзвони Олегу")) }
    }

    @Test func missingContactIsTruthfullyUnavailable() async {
        let executor = ProductionCanonicalCapabilityExecutor(contacts: CallContactResolverStub(.notFound), personalSearchSources: [])
        await #expect(throws: CanonicalCapabilityExecutionError.unavailable("contact_not_found")) { try await executor.execute(LocalCommandEngine().parse("Подзвони Невідомому")) }
    }
}
