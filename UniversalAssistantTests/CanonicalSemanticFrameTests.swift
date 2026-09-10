import Testing
@testable import UniversalAssistant

struct CanonicalSemanticFrameTests {
    private let parser = LocalCommandEngine()

    @Test func sourceRoleWinsCrossFamilyCollision() {
        let photos = parser.parse("Пошукай рахунки серед моїх фотографій")
        #expect(photos.intent == .photoSearch)

        let files = parser.parse("Дай вибрати контракт із iCloud Drive")
        #expect(files.intent == .fileSearch)
    }

    @Test func contactQuestionAndCallChannelRemainDistinct() {
        let lookup = parser.parse("Чи збережений у мене контакт Марко?")
        #expect(lookup.intent == .contactLookup)
        #expect(lookup.entities["contact"] == "Марко")

        let telephone = parser.parse("Набери Марка")
        #expect(telephone.intent == .contactCall)
        #expect(telephone.entities["call_service"] == nil)

        let thirdParty = parser.parse("Подзвони Маркові через WhatsApp")
        #expect(thirdParty.intent == .contactCall)
        #expect(thirdParty.entities["call_service"] == "whatsapp")
    }

    @Test func unicodeFoldingKeepsEntitySlicesOwnedByTheOriginalTranscript() {
        let analyzer = CanonicalSemanticFrameAnalyzer()
        let cases = [
            ("Зателефонуйте Євгенії", "Євгенії"),
            ("Наберіть Ївгу", "Ївгу"),
            ("CALL José", "José")
        ]

        for (input, expectedContact) in cases {
            let result = analyzer.analyze(original: input, normalized: input.lowercased())
            #expect(result.intent == .contactCall)
            #expect(result.entities["contact"] == expectedContact)
        }
    }

    @Test func compositionPreservesTargetAndSourceRoles() {
        let weather = parser.parse("Скажи температуру тут")
        #expect(weather.intent == .weather)
        #expect(weather.entities["near_current_location"] == "true")

        let media = parser.parse("Відкрий плейлист у Spotify")
        #expect(media.intent == .mediaSearch)
        #expect(media.entities["app"] == "Spotify")

        let application = parser.parse("Відкрий Spotify")
        #expect(application.intent == .open)
    }

    @Test func captureAndRecordingFamiliesResolveBeforeWebFallback() {
        #expect(parser.parse("Оцифруй цей паперовий документ").intent == .cameraCapture)
        #expect(parser.parse("Проскануй штрихкод товару").intent == .cameraCapture)
        #expect(parser.parse("Розпочни аудіозапис зустрічі").intent == .audioRecord)
    }

    @Test func latestPhotoActionIsRetained() {
        let command = parser.parse("Надішли найсвіжіший знімок із Photos")
        #expect(command.intent == .photoSearch)
        #expect(command.entities["query"] == "recent")
        #expect(command.entities["requested_action"] == "share")
    }

    @Test func temporalAndNumericRolesPreserveOrderedParameters() {
        let timer = parser.parse("Встанови таймер на 2,5 хвилини для чаю")
        #expect(timer.intent == .deviceAction)
        #expect(timer.entities["duration_seconds"] == "150")
        #expect(timer.entities["numeric_tokens"] == "2.5")
        #expect(timer.entities["temporal_expression"] == "Встанови таймер на 2,5 хвилини для чаю")

        let percentage = parser.parse("Зменш 880 на 12,5 відсотка")
        #expect(percentage.intent == .localUtility)
        #expect(percentage.entities["numeric_tokens"] == "880|12.5")
        #expect(percentage.entities["percentage"] == "12.5")
    }

    @Test func compoundAndContextRolesSurviveCapabilitySelection() {
        let route = parser.parse("Проклади маршрут до музею, потім знайди каву по дорозі")
        #expect(route.entities["context_reference"] == "activeRoute")
        #expect(route.entities["compound_clause_count"] == "2")
        #expect(route.entities["compound_order"] == "sequential")

        let shared = parser.parse("Прочитай текст на цій фотографії")
        #expect(shared.entities["context_reference"] == "sharedContent")
    }

    @Test func settingsTargetsRemainStructurallyDistinct() {
        let application = parser.parse("Покажи параметри для цього додатку")
        #expect(application.intent == .settings)
        #expect(application.entities["settings_target"] == "application")

        for phrase in ["Відкрий системні параметри пристрою", "Параметри мобільної мережі", "Show general phone settings"] {
            let system = parser.parse(phrase)
            #expect(system.intent == .settings)
            #expect(system.entities["settings_target"] == "system")
            #expect(system.intent != .webSearch)
        }
    }

    @Test func temporalActionObjectCompositionSeparatesCreatesFromQueries() {
        let recordedEvent = parser.parse("Запиши на післязавтра о 16:20 огляд проєкту")
        #expect(recordedEvent.intent == .calendarCreate)
        let setEvent = parser.parse("Додай у календар наступного понеділка о 11:10 консультацію")
        #expect(setEvent.intent == .calendarCreate)
        let query = parser.parse("Покажи календар на наступний понеділок")
        #expect(query.intent == .calendarQuery)
        let arithmetic = parser.parse("Сто поділити на п’ять і помножити на дев’ять")
        #expect(arithmetic.intent == .localUtility)
    }

    @Test func temporalFamiliesProduceTypedPayloadsFromUnseenActionForms() {
        let reminder = parser.parse("Встанови нагадування сьогодні о 18:35 забрати пакунок")
        #expect(reminder.intent == .reminderCreate)

        let timer = parser.parse("Увімкни таймер для заварювання на сорок п'ять секунд")
        #expect(timer.intent == .deviceAction)
        #expect(timer.entities["system_action"] == "timer")
        #expect(timer.entities["duration_seconds"] == "45")

        let alarm = parser.parse("Розбуди мене о 06:25 для раннього потяга")
        #expect(alarm.intent == .deviceAction)
        #expect(alarm.entities["system_action"] == "alarm")
        #expect(alarm.entities["hour"] == "06")
        #expect(alarm.entities["minute"] == "25")

        let query = parser.parse("Перелік нагадувань на післязавтра")
        #expect(query.intent == .reminderQuery)
    }
}
