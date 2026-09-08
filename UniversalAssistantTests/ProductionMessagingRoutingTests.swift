import Foundation
import Testing
@testable import UniversalAssistant

private actor MessageContactResolverStub: ContactResolving {
    let resolution: ContactResolution
    init(_ resolution: ContactResolution) { self.resolution = resolution }
    func requestAccessIfNeeded() async throws {}
    func resolve(name: String) async throws -> ContactResolution { resolution }
    func resolve(exactIdentifier identifier: String) async throws -> ContactResolution { resolution }
}

@Suite("Production messaging routing")
@MainActor
struct ProductionMessagingRoutingTests {
    private var contact: ContactCandidate {
        .init(identifier: "olena", displayName: "Олена", phoneNumbers: ["+380 67 111 22 33"])
    }

    @Test func unseenNaturalRecipientUsesSystemMessagesComposer() async throws {
        let executor = ProductionCanonicalCapabilityExecutor(
            contacts: MessageContactResolverStub(.resolved(contact)),
            personalSearchSources: []
        )
        let command = LocalCommandEngine().parse("Надішли повідомлення Олені")
        #expect(command.intent == .messageCompose)
        guard case let .presentation(.message(recipients, _)) = try await executor.execute(command) else {
            Issue.record("Expected public Messages composer"); return
        }
        #expect(recipients == ["380671112233"])
    }

    @Test func explicitWhatsAppUsesOfficialHandoffAndNeverSystemComposer() async throws {
        let executor = ProductionCanonicalCapabilityExecutor(
            contacts: MessageContactResolverStub(.resolved(contact)),
            personalSearchSources: []
        )
        let command = LocalCommandEngine().parse("Напиши Олені через WhatsApp")
        #expect(command.entities["message_service"] == "whatsapp")
        guard case let .handoff(result) = try await executor.execute(command) else {
            Issue.record("Expected WhatsApp handoff"); return
        }
        #expect(result.destination.absoluteString == "https://wa.me/380671112233")
    }

    @Test func unresolvedAndAmbiguousRecipientsTerminateTruthfully() async {
        let missing = ProductionCanonicalCapabilityExecutor(
            contacts: MessageContactResolverStub(.notFound),
            personalSearchSources: []
        )
        await #expect(throws: CanonicalCapabilityExecutionError.unavailable("message_contact_not_found")) {
            try await missing.execute(LocalCommandEngine().parse("Напиши повідомлення Артемові"))
        }

        let choices = [
            ContactCandidate(identifier: "1", displayName: "Олена", phoneNumbers: ["1111111"]),
            ContactCandidate(identifier: "2", displayName: "Олена Робота", phoneNumbers: ["2222222"])
        ]
        let ambiguous = ProductionCanonicalCapabilityExecutor(
            contacts: MessageContactResolverStub(.ambiguous(choices)),
            personalSearchSources: []
        )
        await #expect(throws: CanonicalCapabilityExecutionError.ambiguous(["Олена", "Олена Робота"])) {
            try await ambiguous.execute(LocalCommandEngine().parse("Надішли повідомлення Олені"))
        }
    }
}
