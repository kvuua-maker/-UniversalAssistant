import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Messaging integration") struct MessagingIntegrationTests {
    let planner = MessengerHandoffPlanner()

    @Test func messagesUsesSystemComposerAndNeverClaimsHistory() throws {
        #expect(try planner.plan(messenger: .messages, recipient: "+380 67 123 45 67", body: "Привіт") ==
            .systemComposer(recipients: ["380671234567"], body: "Привіт"))
        let evidence = try #require(MessengerHandoffPlanner.evidence.first { $0.messenger == .messages })
        #expect(evidence.supported == [.compose])
        #expect(!evidence.supported.contains(.searchHistory))
    }

    @Test func exactMessengerHandoffsEncodeUserControlledDraft() throws {
        guard case let .verifiedHandoff(whatsapp) = try planner.plan(messenger: .whatsapp, recipient: "+380671234567", body: "A & B") else { Issue.record("expected WhatsApp handoff"); return }
        #expect(whatsapp.host == "wa.me")
        #expect(URLComponents(url: whatsapp, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "A & B")
        guard case let .verifiedHandoff(telegram) = try planner.plan(messenger: .telegram, recipient: "@durov", body: "Hello") else { Issue.record("expected Telegram handoff"); return }
        #expect(telegram.scheme == "tg")
        guard case let .verifiedHandoff(viber) = try planner.plan(messenger: .viber, recipient: nil, body: "Hello") else { Issue.record("expected Viber handoff"); return }
        #expect(viber.scheme == "viber")
    }

    @Test func signalAndInvalidRecipientAreTruthful() throws {
        #expect(try planner.plan(messenger: .signal, recipient: nil, body: "Hi") == .unavailable(reason: "use_system_share_sheet_to_choose_signal"))
        #expect(throws: MessagingPlanningError.invalidRecipient) { try planner.plan(messenger: .whatsapp, recipient: "Bob", body: nil) }
    }

    @Test func everyClaimedSendRequiresUserConfirmation() {
        #expect(MessengerHandoffPlanner.evidence.allSatisfy { $0.userConfirmationRequired })
        #expect(MessengerHandoffPlanner.evidence.allSatisfy { !$0.supported.contains(.send) })
    }
}
