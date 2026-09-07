import Speech
import Testing
@testable import UniversalAssistant

struct VoiceTextInputQualityTests {
    private let engine = LocalCommandEngine()

    @Test func speechRequestUsesSupportedQualityConfiguration() {
        let request = SFSpeechAudioBufferRecognitionRequest()
        VoiceRecognitionRequestConfiguration().apply(to: request)
        #expect(request.shouldReportPartialResults)
        #expect(request.addsPunctuation)
        #expect(request.taskHint == .search)
        #expect(request.contextualStrings == VoiceRecognitionRequestConfiguration.contextualVocabulary)
        #expect(request.contextualStrings.count <= 100)
        #expect(request.contextualStrings.allSatisfy { $0.split(separator: " ").count <= 2 })
        #expect(["NVIDIA", "Baldinini", "Spotify", "Apple Music", "QR-код", "відскануй", "розпізнай"].allSatisfy(request.contextualStrings.contains))
    }

    @Test func genericQueryDoesNotAddInternalFindOperator() throws {
        let intent = try GenericIntentParser().parse("Хто зараз президент Аргентини?")
        let query = try GenericQuerySanitizer().query(for: intent)
        #expect(!query.lowercased().hasPrefix("find "))
        #expect(query.contains("Хто зараз президент Аргентини?"))
    }

    @Test func userAuthoredFindIsPreserved() throws {
        let intent = try GenericIntentParser().parse("Find Find My documentation")
        #expect(try GenericQuerySanitizer().query(for: intent).hasPrefix("Find Find My"))
    }

    @Test("Semantic capability precedence", arguments: [
        ("Куди піти випити кави?", CommandIntent.placeSearch),
        ("Куда сходить выпить кофе?", .placeSearch),
        ("Де поруч кав'ярня?", .placeSearch),
        ("Хочу придбати футболку", .fashionDiscovery),
        ("Хочу купить кроссовки", .fashionDiscovery),
        ("Скільки коштує молоко в Сільпо?", .groceryBasket),
        ("Сколько стоит хлеб в супермаркете?", .groceryBasket),
        ("Хочу купити ноутбук", .productSearch)
    ])
    func semanticCapabilityPrecedesBroadFallback(_ phrase: String, _ expected: CommandIntent) {
        #expect(engine.parse(phrase).intent == expected)
    }

    @Test("Build 23 capability routing regressions", arguments: [
        ("Знайди найближчу кав'ярню", CommandIntent.placeSearch),
        ("Найди ближайшую кофейню", .placeSearch),
        ("Знайди магазин спортивного бренду у Києві, який сьогодні працює, і покажи маршрут", .placeSearch),
        ("Створи завтра о п'ятнадцятій подію Тест", .calendarCreate),
        ("Запиши голосову замітку", .audioRecord),
        ("Покажи мої останні фотографії", .photoSearch),
        ("Увімкни композицію у Apple Music", .mediaSearch)
    ])
    func build23SpecificCapabilitiesPrecedeBroadPatterns(_ phrase: String, _ expected: CommandIntent) {
        #expect(engine.parse(phrase).intent == expected)
    }

    @Test func build23EntitiesAreReusableAndDoNotContainExecutionContext() {
        let contact = engine.parse("Знайди контакт Мама на моєму iPhone")
        #expect(contact.entities["contact"] == "Мама")
        let place = engine.parse("Знайди магазин у Києві, який сьогодні працює, і покажи маршрут")
        #expect(place.entities["location"] == "Києві")
        let media = engine.parse("Увімкни композицію Example Artist в Apple Music")
        #expect(media.entities["query"] == "композицію Example Artist")
    }

    @Test func broadInformationAndAmbiguityRemainFallbacks() {
        #expect(engine.parse("Хто зараз президент Аргентини?").intent == .unknown)
        #expect(engine.parse("Найди свежую информацию о компании Nvidia").intent == .unknown)
        #expect(engine.parse("Щось цікаве").needsClarification)
    }

    @Test func adaptiveComposerUsesOneSharedBoundedInputSurface() {
        #expect(RequestComposerLayoutPolicy.minimumLines == 1)
        #expect(RequestComposerLayoutPolicy.maximumLines >= 4)
        #expect(RequestComposerLayoutPolicy.maximumLines <= 8)
    }

    @Test func build24PhysicalParserRegressionsUseCanonicalRoutes() {
        let qr = engine.parse("Відскануй QR-код")
        #expect(qr.intent == .cameraCapture); #expect(qr.entities["capture_mode"] == "code_scan")
        let ocr = engine.parse("Розпізнай текст камерою")
        #expect(ocr.intent == .cameraCapture); #expect(ocr.entities["capture_mode"] == "text_scan")
        let timer = engine.parse("Постав таймер на 2 хвилини")
        #expect(timer.intent == .deviceAction); #expect(timer.entities["duration_seconds"] == "120")
        let alarm = engine.parse("Постав будильник на 4:00")
        #expect(alarm.intent == .deviceAction); #expect(alarm.entities["hour"] == "4"); #expect(alarm.entities["minute"] == "00")
        #expect(engine.parse("Відкрий останнє фото").intent == .photoSearch)
    }

    @Test func translationControlLanguageDoesNotLeakIntoPayload() {
        let command = engine.parse("Переклади англійською: Добрий вечір, як справи?")
        #expect(command.intent == .translation)
        #expect(command.entities["target_language"] == "en")
        #expect(command.entities["source_text"] == "Добрий вечір, як справи")
    }

    @Test func build25SemanticVariantsConvergeOnCanonicalIntents() {
        #expect(engine.parse("Відкрий найновіше фото").intent == .photoSearch)
        #expect(engine.parse("Відкрий найновіше фото").entities["query"] == "")
        #expect(engine.parse("Що в мене заплановано на завтра?").intent == .calendarQuery)
        let navigation = engine.parse("Проклади маршрут до залізничного вокзалу")
        #expect(navigation.intent == .navigation)
        #expect(navigation.entities["destination"] == "залізничного вокзалу")
        #expect(engine.parse("Покажи найближчу аптеку").intent == .placeSearch)
        #expect(engine.parse("Де найближча заправка?").intent == .placeSearch)
        #expect(engine.parse("Створи нову нотатку: купити молоко").intent == .noteCreate)
    }

    @Test func remainingSystemFamiliesNeverBecomeWebSearch() {
        let publicCases: [(String, String)] = [
            ("Увімкни ліхтарик", "flashlight"),
            ("Вимкни ліхтарик", "flashlight"),
            ("Покажи заряд батареї у відсотках", "battery"),
            ("Скільки вільного місця на моєму iPhone?", "storage"),
            ("Скопіюй у буфер: зустріч завтра о десятій", "clipboard")
        ]
        for (phrase, action) in publicCases {
            let command = engine.parse(phrase)
            #expect(command.intent == .deviceAction)
            #expect(command.entities["system_action"] == action)
        }
        let limited = [
            "Відкрий налаштування Wi-Fi", "Налаштування Wi-Fi", "Увімкни Bluetooth",
            "Увімкни режим енергозбереження", "Зменш яскравість екрана",
            "Збільш гучність до половини", "Покажи мої пропущені дзвінки",
            "Відкрий калькулятор", "Відкрий програму Телефон", "Покажи мої контакти", "Покажи мої будильники"
        ]
        for phrase in limited {
            let command = engine.parse(phrase)
            #expect(command.intent == .deviceAction)
            #expect(command.entities["system_action"] == "unsupported_system_control")
        }
    }

    @Test func asrQrVariantsRecoverOnlyInsideScannerContext() {
        for phrase in ["Відскануй Q Club", "Скануй quad", "Розпізнай Q клуб"] {
            let command = engine.parse(phrase)
            #expect(command.intent == .cameraCapture)
            #expect(command.entities["capture_mode"] == "code_scan")
        }
        #expect(engine.parse("Розкажи про Quad").intent != .cameraCapture)
    }
}
