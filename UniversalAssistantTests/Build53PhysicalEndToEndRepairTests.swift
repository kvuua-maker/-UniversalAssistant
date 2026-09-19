import Foundation
import Testing
@testable import UniversalAssistant

@Suite("Build 53 physical end-to-end root repairs")
struct Build53PhysicalEndToEndRepairTests {
    private let parser = LanguageUnderstandingBlock()

    @Test func explicitCurrentCommandSlotsCannotBeReplacedByDefaultsOrFuzzyEntities() {
        let brand = parser.parse("Купи сорочку Pierre Cardin")
        #expect(brand.constraints.brand == "Pierre Cardin")
        #expect(brand.entities["brand"] == "Pierre Cardin")
        #expect(brand.entities["brand"] != "Prada")

        let phone = parser.parse("Подзвони мамі на телефон")
        #expect(phone.intent == .contactCall)
        #expect(phone.entities["call_service"] == "telephone")

        let viber = parser.parse("Набери маму через Viber")
        #expect(viber.intent == .contactCall)
        #expect(viber.entities["call_service"] == "viber")
        #expect(viber.entities["call_service"] != "whatsapp")

        let weather = parser.parse("Погода на завтра Київ")
        #expect(weather.intent == .weather)
        #expect(weather.entities["location"] == "Київ")
        #expect(weather.entities["near_current_location"] == nil)
        #expect(weather.entities["relative_day_offset"] == "1")

        let weekday = parser.parse("Погода у Львові в п’ятницю")
        #expect(weekday.entities["location"] == "Львові")
        #expect(weekday.entities["weekday"] == "6")

        let date = parser.parse("Погода в Одесі 18 вересня")
        #expect(date.entities["location"] == "Одесі")
        #expect(date.entities["calendar_day"] == "18")

        let implicit = parser.parse("Погода на завтра")
        #expect(implicit.entities["location"] == nil)
        #expect(implicit.entities["near_current_location"] == "true")
    }

    @Test func anUnknownProperNounCannotMutateIntoAnotherRegisteredBrand() {
        let command = parser.parse("Знайди сорочку Loro Piana")
        #expect(command.constraints.brand != "Prada")
        #expect(command.entities["brand"] != "Prada")
        #expect(command.originalText.contains("Loro Piana"))
    }

    @Test @MainActor func explicitBrandReachesOnlyItsOfficialExactDestination() async throws {
        let command = parser.parse("Купи сорочку Pierre Cardin")
        let executor = ProductionCanonicalCapabilityExecutor(personalSearchSources: [])
        guard case let .handoff(handoff) = try await executor.execute(command) else {
            Issue.record("Expected official brand handoff"); return
        }
        #expect(handoff.destination.host == "pierrecardin.com")
        #expect(handoff.destination.path == "/en/search")
        #expect(handoff.destination.absoluteString.localizedCaseInsensitiveContains("prada") == false)
        let query = URLComponents(url: handoff.destination, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "q" })?.value ?? ""
        #expect(query.localizedCaseInsensitiveContains("сорочку"))
    }

    @Test func appRecognitionIsSeparateFromPublicExecutionAvailability() {
        let viber = parser.parse("Відкрий Viber")
        #expect(viber.intent == .open)
        #expect(viber.entities["app"] == "viber")

        let voice = parser.parse(
            "Відкрий",
            speechEvidence: .init(
                primaryTranscript: "Відкрий",
                alternativeTranscripts: ["Відкрий Телеграм"],
                segmentAlternativeTranscripts: ["Телеграм"],
                partialTranscriptHistory: ["Відкрий Телеграм"],
                segmentAlternativeCount: 1,
                averageSegmentConfidence: 0.82
            )
        )
        #expect(voice.intent == .open)
        #expect(voice.entities["app"] == "telegram")
    }

    @Test func voiceMemosOpenAndLocalRecordingAreDifferentCapabilities() {
        let open = parser.parse("Відкрий диктофон")
        #expect(open.intent == .open)
        #expect(open.entities["app"] == "voice-memos")

        let record = parser.parse("Увімкни диктофон")
        #expect(record.intent == .audioRecord)
        #expect(record.entities["recorder_action"] == "start")
        #expect(record.entities["app"] == nil)
    }

    @Test func globalSystemSettingsCommandsNeverBecomeWebOrFakeActions() {
        for phrase in ["Відкрий Wi-Fi", "Відкрий Bluetooth", "Відкрий налаштування на iPhone"] {
            let command = parser.parse(phrase)
            #expect(command.intent == .settings)
            #expect(command.entities["settings_target"] == "system")
            #expect(command.intent != .webSearch)
        }
        let applicationSettings = parser.parse("Відкрий налаштування UniversalAssistant")
        #expect(applicationSettings.intent == .settings)
        #expect(applicationSettings.entities["settings_target"] == "application")
    }

    @Test func appleSpeechVocabularyReservesRegisteredAppsAndChannels() {
        let values = VoiceRecognitionRequestConfiguration.canonicalVocabulary
            .map { $0.lowercased() }
        #expect(values.contains("telegram"))
        #expect(values.contains("телеграм"))
        #expect(values.contains("viber"))
        #expect(values.contains("вайбер"))
        #expect(values.contains("whatsapp"))
        let canonicalEntities = Set(VoiceRecognitionRequestConfiguration.canonicalEntityVocabulary.map { $0.lowercased() })
        #expect(Set(values).isSuperset(of: canonicalEntities))
        #expect(VoiceRecognitionRequestConfiguration.canonicalEntityVocabulary.count <= VoiceRecognitionRequestConfiguration.maximumContextualStringCount)
        #expect(values.count <= VoiceRecognitionRequestConfiguration.maximumContextualStringCount)
    }

    @Test func masterSpeechVocabularyReconcilesEveryRequiredCapabilityFamily() {
        let values = Set(VoiceRecognitionRequestConfiguration.masterVocabulary.map { $0.lowercased() })
        for required in [
            "viber", "telegram", "whatsapp", "youtube", "spotify", "apple music", "wi-fi", "bluetooth",
            "google places", "booking.com", "choiceqr", "reston", "karabas", "multiplex", "планета кіно",
            "ebay", "aliexpress", "amazon", "temu", "prom.ua", "baldinini", "pierre cardin", "adidas",
            "seiko", "нова пошта", "укрпошта", "meest", "glovo", "bolt food", "work.ua", "robota.ua",
            "jobs.ua", "djinni", "dou jobs", "happy monday", "дія", "qr", "ocr", "pdf", "оцифруй"
        ] {
            #expect(values.contains(required), "Missing canonical speech term: \(required)")
        }
    }

    @Test func pdfCreationDoesNotCollideWithCameraWithoutScanEvidence() {
        for text in ["Створи PDF", "Зроби PDF"] {
            let command = parser.parse(text)
            #expect(command.intent == .fileSearch)
            #expect(command.entities["pdf_creation_requested"] == "true")
            #expect(command.entities["capture_mode"] == nil)
        }
        let scan = parser.parse("Відскануй документ у PDF")
        #expect(scan.intent == .cameraCapture)
        #expect(scan.entities["input_source"] == "document_camera")
        #expect(scan.entities["output_format"] == "pdf")
    }

    @Test func genericMessageObjectCannotBecomeAProviderOrConsumeTheRecipient() {
        let command = parser.parse("Надішли Соломії Квантовій повідомлення про зміну часу")
        #expect(command.intent == .messageCompose)
        #expect(command.entities["message_service"] == "messages")
        #expect(command.entities["recipient"] == "Соломії Квантовій")
        #expect(command.entities["message_body"] == "про зміну часу")
    }

    @Test @MainActor func missingPDFSourceEndsInOneSpecificClarificationNotCameraOrFailure() async throws {
        let model = ProductionAssistantComposition.makeModel(
            personalSearchSources: [], compactResultDuration: .seconds(60)
        )
        model.input = "Створи PDF"
        model.submit()
        for _ in 0..<100 {
            if case .clarification = model.resultState { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard case .clarification = model.resultState else {
            Issue.record("PDF without a source must ask one specific clarification")
            return
        }
        #expect(model.statusText == "Що потрібно перетворити на PDF: текст, фото чи файл?")
        #expect(model.capabilityPresentation == nil)
    }

    @Test func mediaPlayIsNotEquivalentToOpeningAnApplication() {
        let play = parser.parse("Увімкни музику")
        #expect(play.intent == .mediaSearch)
        #expect(play.entities["media_action"] == "play")

        let open = parser.parse("Відкрий Apple Music")
        #expect(open.intent == .open)
        #expect(open.entities["media_action"] == nil)
    }

    @Test func exactGoogleFallbackPreservesTheCompleteCommand() throws {
        let request = "Знайди ресторан у Чернівцях завтра о 19:00 на чотирьох"
        let command = StructuredCommand(
            originalText: request, normalizedText: request.lowercased(),
            language: .uk, intent: .unknown
        )
        let url = try ControlledWebSearchHandoff().destination(
            for: command, structuredCapabilityAvailable: false
        )
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "q" })?.value)
        #expect(query == request)
        #expect(url.path == "/search")
    }
}

@Suite("Build 53 contact ambiguity contract")
struct Build53ContactAmbiguityContractTests {
    @Test func duplicateExactNamesAreNeverArbitrarilySelected() async throws {
        let first = ContactCandidate(identifier: "one", displayName: "Іван", phoneNumbers: ["+380501111111"])
        let second = ContactCandidate(identifier: "two", displayName: "Іван", phoneNumbers: ["+380502222222"])
        let resolver = LocalContactResolver(
            authorization: Build53AuthorizedContacts(),
            query: Build53DuplicateContactQuery(values: [first, second])
        )
        let resolution = try await resolver.resolve(name: "Іван")
        guard case let .ambiguous(values) = resolution else {
            Issue.record("Expected all exact same-name contacts"); return
        }
        #expect(Set(values.map(\.identifier)) == ["one", "two"])
        #expect(Set(values.map(\.selectionLabel)).count == 2)
    }
}

private struct Build53AuthorizedContacts: ContactAuthorizing {
    func currentStatus() -> ContactAuthorizationState { .authorized }
    func requestAccess() async throws -> Bool { true }
}

private struct Build53DuplicateContactQuery: ContactQuerying {
    let values: [ContactCandidate]
    func contacts(matching name: String, timeout: Duration) async throws -> [ContactCandidate] { values }
    func contact(identifier: String, timeout: Duration) async throws -> ContactCandidate? {
        values.first { $0.identifier == identifier }
    }
    func accessibleContacts(limit: Int, timeout: Duration) async throws -> [ContactCandidate] {
        Array(values.prefix(limit))
    }
}
