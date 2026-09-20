import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Build 56 single corridor")
struct Build56SingleCorridorArchitectureTests {
    @Test func everyIntentHasTerminalRoom() {
        let router = SingleCorridorRouter()
        for intent in CommandIntent.allCases {
            let command = StructuredCommand(
                originalText: intent.rawValue,
                normalizedText: intent.rawValue,
                language: .uk,
                intent: intent,
                entities: intent == .unknown ? ["query": intent.rawValue] : [:],
                needsClarification: false
            )
            let plan = router.plan(command)
            #expect(ExecutionRoom.allCases.contains(plan.room))
            #expect(!plan.primaryMechanism.isEmpty)
        }
    }

    @Test func atomicCommandRoutesExactlyOnce() {
        let counter = LockedRouteCounter()
        let router = SingleCorridorRouter(decisionObserved: { _ in counter.increment() })
        _ = router.plan(LanguageUnderstandingBlock().parse("Відкрий Telegram"))
        #expect(counter.value == 1)
    }

    @Test func build58ChangedPhysicalFamiliesStillRouteExactlyOnce() {
        let counter = LockedRouteCounter()
        let router = SingleCorridorRouter(decisionObserved: { _ in counter.increment() })
        let block = LanguageUnderstandingBlock()
        let commands = [
            "Відкрий Viber", "Відкрий Telegram", "Відкрий всі фото",
            "Купити кросівки 41 розміру", "Знайди АЗС поруч",
            "Знайди роботу водієм у Києві від 50000"
        ]
        for text in commands { _ = router.plan(block.parse(text)) }
        #expect(counter.value == commands.count)
    }

    @Test func productionRoomsDoNotOwnParserOrRouterFallbacks() throws {
        let testsURL = URL(fileURLWithPath: #filePath)
        let root = testsURL.deletingLastPathComponent().deletingLastPathComponent()
        let forbidden = [
            "UniversalAssistant/Core/CanonicalCapabilityExecutor.swift",
            "UniversalAssistant/Core/ProductionMultiStepCoordinator.swift",
            "UniversalAssistant/Commerce/OfficialPublicProviderHandoffExecutor.swift"
        ]
        for path in forbidden {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            let shippedSource = source.replacingOccurrences(
                of: #"#if DEBUG[\s\S]*?#endif"#,
                with: "", options: .regularExpression
            )
            #expect(!shippedSource.contains("SingleCorridorRouter().plan("), "Nested router ownership in \(path)")
        }
        let coordinator = try String(contentsOf: root.appendingPathComponent("UniversalAssistant/Core/ProductionMultiStepCoordinator.swift"), encoding: .utf8)
        #expect(!coordinator.contains("LanguageUnderstandingBlock()"))
    }

    @Test func explicitChannelsAndProtectedSystemStayFrozen() {
        let parser = LanguageUnderstandingBlock()
        let router = SingleCorridorRouter()
        let phone = router.plan(parser.parse("Подзвони мамі на телефон"))
        #expect(phone.command.entities["call_service"] == "telephone")
        #expect(phone.room == .communication)
        let telegram = router.plan(parser.parse("Напиши мамі у Telegram"))
        #expect(telegram.command.entities["message_service"] == "telegram")
        #expect(telegram.room == .communication)
        let settings = router.plan(parser.parse("Відкрий Bluetooth"))
        #expect(settings.room != .web)
    }

    @Test func informationalWebIsPredeterminedAndNeverHomepage() throws {
        let command = StructuredCommand(
            originalText: "Чому небо синє",
            normalizedText: "чому небо синє",
            language: .uk,
            intent: .webSearch,
            entities: ["query": "Чому небо синє"]
        )
        let plan = SingleCorridorRouter().plan(command)
        #expect(plan.room == .web)
        #expect(plan.terminalStrategy == .exactWeb)
        let url = try ControlledWebSearchHandoff().destination(for: command, structuredCapabilityAvailable: false)
        #expect(url.absoluteString.contains("search"))
        #expect(url.absoluteString != "https://www.google.com")
    }

    @Test func build55VoiceEvidenceRegressions() {
        let parser = LanguageUnderstandingBlock()
        #expect(parser.parse("Відкрий Viber").entities["app"] == "viber")
        #expect(parser.parse("Відкрий Telegram").entities["app"] == "telegram")
        #expect(parser.parse("Напиши мамі у Viber").entities["message_service"] == "viber")
        #expect(parser.parse("Напиши мамі у Telegram").entities["message_service"] == "telegram")
        #expect(parser.parse("Напиши мамі у WhatsApp").entities["message_service"] == "whatsapp")
        #expect(parser.parse("Подзвони Сашко").entities["call_service"] == "telephone")
        #expect(parser.parse("Проскануй QR-код").entities["capture_mode"] == "code_scan")
        #expect(parser.parse("Проскануй штрихкод").entities["capture_mode"] == "code_scan")
        #expect(parser.parse("Відкрий Файли").intent == .open)
    }

    @Test func pdfRoutesDirectlyToCorrectCapability() {
        let parser = LanguageUnderstandingBlock()
        let generic = parser.parse("Зроби PDF")
        #expect(generic.intent == .cameraCapture)
        #expect(generic.entities["input_source"] == "document_camera")
        #expect(generic.entities["output_format"] == "pdf")
        #expect(parser.parse("Зроби PDF з тексту").entities["pdf_source_mode"] == "text")
        #expect(parser.parse("Зроби PDF з фото").entities["pdf_source_mode"] == "photo")
        #expect(parser.parse("Перетвори файл у PDF").entities["pdf_source_mode"] == "document")
    }

    @Test func sharedSemanticNormalizationAndProviderOwnership() {
        #expect(CanonicalLocalityNormalizer.normalize("у Львові") == "Львів")
        #expect(CanonicalLocalityNormalizer.normalize("в Києві") == "Київ")
        let parser = LanguageUnderstandingBlock()
        let weather = parser.parse("Покажи погоду у Львові в п'ятницю")
        #expect(weather.entities["location"] == "Львів")
        #expect(weather.entities["weekday"] != nil)
        let brand = parser.parse("Купи сорочку Pierre Cardin")
        #expect(brand.constraints.brand == "Pierre Cardin")
        #expect(!CanonicalProductQueryBuilder.query(for: brand, selectedProviderOrBrand: "Pierre Cardin").lowercased().contains("куп"))
        let event = parser.parse("Знайди квитки на концерт у Львові на вихідні")
        let plan = SingleCorridorRouter().plan(event)
        #expect(plan.providerID == "events.karabas")
        #expect(plan.terminalStrategy == .exactWeb)
    }

    @Test func calendarAndReminderAreDeterministicWhenComplete() {
        let calendar = VoiceDeterministicCommandAssessment(text: "Створи подію завтра о 15:00 зустріч")
        #expect(calendar.command.intent == .calendarCreate)
        #expect(calendar.isResolvedDeterministic)
        #expect(EventKitCommandArgumentExtractor().extract(calendar.command).subject == "зустріч")
        let reminder = VoiceDeterministicCommandAssessment(text: "Нагадай завтра о 9 купити хліб")
        #expect(reminder.command.intent == .reminderCreate)
        #expect(reminder.isResolvedDeterministic)
    }

    @Test func incompleteAppleEvidenceUsesComplementaryRealRole() {
        let selected = VoiceAuthoritativeTranscriptSelector.select(
            groq: "Viber",
            appleFallback: "Відкрий"
        )
        #expect(selected?.text.lowercased().contains("viber") == true)
        let message = VoiceAuthoritativeTranscriptSelector.select(
            groq: "Telegram",
            appleFallback: "Напиши мамі"
        )
        #expect(message?.text.lowercased().contains("telegram") == true)
    }

    @Test func productionEnginesHaveTruthfulReachability() {
        let expected = Set([
            "HotelSearchEngine", "TicketEngine", "RideComparisonEngine", "TravelPlanEngine",
            "JobsDiscoveryEngine", "ParcelDeliveryEngine", "FoodDeliveryComparisonEngine",
            "AppointmentEngine", "GovernmentLocalServicesEngine", "GmailEmailProvider",
            "UniversalAudioDeviceCoordinator", "CommerceSearchEngine"
        ])
        #expect(Set(ProductionEngineReachability.records.map(\.engineID)) == expected)
        #expect(ProductionEngineReachability.records.allSatisfy { !$0.terminalMechanism.isEmpty })
    }
}

private final class LockedRouteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0
    func increment() { lock.lock(); storage += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return storage }
}
