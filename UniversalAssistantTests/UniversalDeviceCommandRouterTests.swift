import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Universal device and outside-world command routing")
struct UniversalDeviceCommandRouterTests {
    private var router: UniversalDeviceCommandRouter {
        .init(applications: .init(applications: LaunchDeviceApplications.verified))
    }

    @Test func sameEntryRoutesLocalExternalAndDeviceCommands() {
        let parser = LocalCommandEngine()
        #expect(router.route(parser.parse("Нагадай купити молоко")) ==
                .local(.init(target: .eventKitReminders, depth: .direct, reason: "system_first_reminders")))
        #expect(router.route(parser.parse("Покажи погоду")) == .externalCapability(.weather))
        guard case let .deviceApplication(app, destination, silent) = router.route(parser.parse("Відкрий Telegram")) else {
            Issue.record("Telegram must resolve directly"); return
        }
        #expect(app.id == "telegram" && destination.scheme == "tg" && silent)
    }

    @Test func exactAliasDoesNotUseArbitraryFuzzySelection() {
        let apps = LaunchDeviceApplications.verified + [
            .init(id: "telegram-alt", aliases: ["телега"], launchURL: URL(string: "https://example.com/telegram")!, exactContext: nil)
        ]
        #expect(DeviceApplicationResolver(applications: apps).resolve(spokenName: "телега") ==
                .clarification(["telegram", "telegram-alt"]))
        #expect(DeviceApplicationResolver(applications: apps).resolve(spokenName: "telegrm") == .unsupported)
    }

    @Test func publiclyDocumentedExactContextBeatsGenericLaunch() {
        let command = LocalCommandEngine().parse("Відкрий Telegram")
        guard case let .deviceApplication(_, destination, silent) = router.route(command, exactContext: "durov") else {
            Issue.record("Expected exact context"); return
        }
        #expect(destination.absoluteString.contains("domain=durov"))
        #expect(silent)
    }
}
