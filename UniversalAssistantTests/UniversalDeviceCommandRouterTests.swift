import Foundation
import Testing
@testable import UniversalAssistant

@MainActor
private final class DeviceApplicationOpenCapture {
    private(set) var values: [URL] = []
    func open(_ value: URL) { values.append(value) }
}

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

    @Test func scopedConfidenceRecoveryPreservesExactAmbiguityAndRejectsWeakCandidates() {
        let apps = LaunchDeviceApplications.verified + [
            .init(id: "telegram-alt", aliases: ["телега"], launchURL: URL(string: "https://example.com/telegram")!, exactContext: nil)
        ]
        #expect(DeviceApplicationResolver(applications: apps).resolve(spokenName: "телега") ==
                .clarification(["telegram", "telegram-alt"]))
        guard case let .direct(recovered) = DeviceApplicationResolver(applications: LaunchDeviceApplications.verified).resolve(spokenName: "telegrm") else { Issue.record("Expected high-confidence unique registry recovery"); return }
        #expect(recovered.id == "telegram")
        #expect(DeviceApplicationResolver(applications: apps).resolve(spokenName: "unrelated assistant") == .unsupported)
    }

    @Test @MainActor func clippedVerifiedAppNamesRecoverByScopedEvidenceThroughReleaseRoot() async throws {
        let expected: [(String, String)] = [
            ("Whats", "whatsapp"),
            ("Telegr", "telegram"),
            ("Spotif", "spotify")
        ]
        let resolver = DeviceApplicationResolver(applications: LaunchDeviceApplications.verified)
        for (noisy, identifier) in expected {
            guard case let .direct(app) = resolver.resolve(spokenName: noisy) else {
                Issue.record("Expected scoped recovery for \(noisy)")
                continue
            }
            #expect(app.id == identifier)
        }
        #expect(DeviceApplicationResolver(applications: LaunchDeviceApplications.verified).resolve(spokenName: "Vibe") == .unsupported)
        let recognizedViber = LanguageUnderstandingBlock().parse("Open Vibe")
        #expect(recognizedViber.intent == .open)
        #expect(recognizedViber.entities["app"] == "viber")

        let capture = DeviceApplicationOpenCapture()
        let model = ProductionAssistantComposition.makeModel(
            personalSearchSources: [],
            compactResultDuration: .seconds(60),
            systemHandoffOpen: capture.open
        )
        model.input = "Open Whats"
        model.submit()
        for _ in 0..<200 where capture.values.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(capture.values.first?.absoluteString == "whatsapp://app")
        #expect(model.statusText != AppText.value("clarification_needed"))
    }

    @Test func appWordVariantsResolveOnlyVerifiedPublicDestinations() {
        guard case let .deviceApplication(youtube, destination, _) = router.route(LocalCommandEngine().parse("Відкрий програму YouTube")) else { Issue.record("Expected verified YouTube handoff"); return }
        #expect(youtube.id == "youtube")
        #expect(destination.host == "www.youtube.com")
        guard case let .deviceApplication(mail, mailDestination, _) = router.route(LocalCommandEngine().parse("Відкрий програму Mail")) else { Issue.record("Expected public mailto handoff"); return }
        #expect(mail.id == "mail")
        #expect(mailDestination.scheme == "mailto")
        #expect(router.route(LocalCommandEngine().parse("Відкрий програму Калькулятор")) == .unsupported(reason: "no_verified_public_app_mechanism"))
    }

    @Test func publiclyDocumentedExactContextBeatsGenericLaunch() {
        let command = LocalCommandEngine().parse("Відкрий Telegram")
        guard case let .deviceApplication(_, destination, silent) = router.route(command, exactContext: "durov") else {
            Issue.record("Expected exact context"); return
        }
        #expect(destination.absoluteString.contains("domain=durov"))
        #expect(silent)
    }

    @Test func officialAppleSiteUsesVerifiedFirstPartyDestination() {
        let command = LocalCommandEngine().parse("Відкрий сайт Apple")
        #expect(command.intent == .open)
        #expect(command.entities["app"] == "сайт Apple")
        guard case .direct = DeviceApplicationResolver(applications: LaunchDeviceApplications.verified).resolve(spokenName: "сайт Apple") else { Issue.record("Resolver did not normalize site prefix"); return }
        guard case let .deviceApplication(app, destination, silent) = router.route(command) else { Issue.record("Expected verified Apple website"); return }
        #expect(app.id == "apple-website")
        #expect(destination.host == "www.apple.com")
        #expect(silent)
    }
}
