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
        #expect(command.entities["query"] == "latest")
    }
}
