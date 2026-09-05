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
}
