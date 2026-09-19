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

    @Test func explicitEmailResolvesTheSameContactDomainAndPopulatesRecipient() async throws {
        let contact = ContactCandidate(
            identifier: "unseen-email",
            displayName: "Катерина Бойко",
            phoneNumbers: ["+380 67 111 22 33"],
            emailAddresses: ["kateryna.b@example.org"]
        )
        let executor = ProductionCanonicalCapabilityExecutor(
            contacts: MessageContactResolverStub(.resolved(contact)),
            personalSearchSources: []
        )
        let command = StructuredCommand(
            originalText: "Надішли Катерині Бойко електронного листа",
            normalizedText: "надішли катерині бойко електронного листа",
            language: .uk,
            intent: .messageCompose,
            entities: ["message_service": "email", "recipient": "Катерині Бойко"]
        )
        guard case let .presentation(.email(recipients, _, _)) = try await executor.execute(command) else {
            Issue.record("Expected Mail composer with resolved address")
            return
        }
        #expect(recipients == ["kateryna.b@example.org"])
    }

    @Test func missingOrMultipleContactEmailsNeverOpenAnUnaddressedComposerSilently() async {
        let command = StructuredCommand(
            originalText: "Напиши електронного листа Романові Ковалю",
            normalizedText: "напиши електронного листа романові ковалю",
            language: .uk,
            intent: .messageCompose,
            entities: ["message_service": "email", "recipient": "Романові Ковалю"]
        )
        let noEmail = ContactCandidate(identifier: "no-email", displayName: "Роман Коваль", phoneNumbers: [])
        let missingExecutor = ProductionCanonicalCapabilityExecutor(
            contacts: MessageContactResolverStub(.resolved(noEmail)), personalSearchSources: []
        )
        await #expect(throws: CanonicalCapabilityExecutionError.unavailable("contact_has_no_email_address")) {
            try await missingExecutor.execute(command)
        }
        let multiple = ContactCandidate(identifier: "multi-email", displayName: "Роман Коваль", phoneNumbers: [], emailAddresses: ["roman@example.org", "work@example.org"])
        let ambiguousExecutor = ProductionCanonicalCapabilityExecutor(
            contacts: MessageContactResolverStub(.resolved(multiple)), personalSearchSources: []
        )
        await #expect(throws: CanonicalCapabilityExecutionError.ambiguous(["roman@example.org", "work@example.org"])) {
            try await ambiguousExecutor.execute(command)
        }
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
        do {
            _ = try await ambiguous.execute(LocalCommandEngine().parse("Надішли повідомлення Олені"))
            Issue.record("Expected contact disambiguation")
        } catch let CanonicalCapabilityExecutionError.ambiguousContacts(values) {
            #expect(Set(values.map(\.identifier)) == ["1", "2"])
        } catch { Issue.record("Unexpected error: \(error)") }
    }
}

@Suite("Production app-content and clipboard composition")
@MainActor
struct ProductionAppContentCompositionTests {
    @Test func unseenRemainingFamiliesReachConcreteCanonicalCapabilities() async throws {
        let cases: [(String, CommandIntent)] = [
            ("Запусти запис голосової замітки для наради", .audioRecord),
            ("Проскануй паперовий договір у PDF", .cameraCapture),
            ("Покажи тривалість поїздки до Львова", .deviceAction),
            ("Відкрий добірку для концентрації у Spotify", .mediaSearch)
        ]
        for (input, expected) in cases {
            let command = LocalCommandEngine().parse(input)
            #expect(command.intent == expected, "\(input) resolved as \(command.intent.rawValue)")
            #expect(command.intent != .webSearch)
        }
        let scanner = LocalCommandEngine().parse("Проскануй паперовий договір у PDF")
        #expect(scanner.entities["input_source"] == "document_camera")
        #expect(try await ProductionCanonicalCapabilityExecutor(personalSearchSources: []).execute(scanner) == .presentation(.scanDocument(.pdf)))
    }

    @Test func spotifyContentNeverSilentlyRunsThroughAppleMusic() async throws {
        let executor = ProductionCanonicalCapabilityExecutor(personalSearchSources: [])
        let command = LocalCommandEngine().parse("Знайди добірку для бігу в Spotify")
        #expect(command.intent == .mediaSearch)
        #expect(command.entities["app"] == "Spotify")
        guard case let .handoff(result) = try await executor.execute(command) else {
            Issue.record("Expected documented Spotify app handoff"); return
        }
        #expect(result.destination.absoluteString == "spotify:")
    }

    @Test func clipboardURLRolesReachThePublicUserInitiatedBoundary() async throws {
        let expected = URL(string: "https://developer.apple.com/documentation")!
        let executor = ProductionCanonicalCapabilityExecutor(
            clipboardRead: { .url(expected) },
            personalSearchSources: []
        )
        let input = "Перейди за вебадресою з буфера"
        let frame = CanonicalSemanticFrameAnalyzer().analyze(original: input, normalized: input.lowercased())
        #expect(frame.frame.action == .open)
        #expect(frame.frame.object == .url)
        #expect(frame.frame.source == .clipboard)
        #expect(frame.intent == .deviceAction)
        let command = LocalCommandEngine().parse(input)
        #expect(command.intent == .deviceAction)
        #expect(command.entities["system_action"] == "clipboard_open_url")
        guard case let .handoff(result) = try await executor.execute(command) else {
            Issue.record("Expected exact clipboard URL handoff"); return
        }
        #expect(result.destination == expected)
    }
}
