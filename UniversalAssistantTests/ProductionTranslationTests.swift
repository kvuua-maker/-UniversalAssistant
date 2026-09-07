import Testing
import Foundation
@testable import UniversalAssistant

@Suite("Production local Apple translation")
@MainActor
struct ProductionTranslationTests {
    @Test func planRequiresExplicitTextAndTarget() throws {
        let plan = try CameraIntelligenceCore().translationPlan(text: " Вихід ", sourceLanguage: "uk", targetLanguage: "en")
        #expect(plan.text == "Вихід")
        #expect(plan.targetLanguage == "en")
        #expect(plan.usesLocalOrSystemFramework)
        #expect(!plan.narrate)
    }
    @Test func missingTargetIsTruthful() {
        #expect(throws: CameraIntelligenceError.invalidTargetLanguage) { try CameraIntelligenceCore().translationPlan(text: "Вихід", sourceLanguage: nil, targetLanguage: "") }
    }
    @Test func appleResponseBindsTypedObservedResult() throws {
        let plan = try CameraIntelligenceCore().translationPlan(text: "Вихід", sourceLanguage: "uk", targetLanguage: "en")
        let result = try TranslationProductionBoundary().result(plan: plan, translatedText: "Exit", sourceLanguage: Locale.Language(identifier: "uk"), targetLanguage: Locale.Language(identifier: "en"))
        #expect(result.sourceText == "Вихід")
        #expect(result.translatedText == "Exit")
        #expect(result.sourceLanguage == "uk")
        #expect(result.targetLanguage == "en")
    }
    @Test func emptyAppleResponseIsTruthful() throws {
        let plan = try CameraIntelligenceCore().translationPlan(text: "Вихід", sourceLanguage: nil, targetLanguage: "en")
        #expect(throws: TranslationProductionError.emptyResult) { try TranslationProductionBoundary().result(plan: plan, translatedText: " ", sourceLanguage: Locale.Language(identifier: "uk"), targetLanguage: Locale.Language(identifier: "en")) }
    }
    @Test func ocrContinuationPresentsTargetSelectionThenOfficialTranslation() throws {
        let model = AssistantViewModel()
        let ocr = OCRProductionResult(recognizedText: "Вихід", provenance: .camera, actions: [.translate])
        model.performOCRAction(ocr, .translate)
        #expect(model.capabilityPresentation == .translationTarget("Вихід"))
        model.startTranslation("Вихід", "en")
        guard case let .translation(plan) = model.capabilityPresentation else { Issue.record("Expected Apple translation presentation"); return }
        #expect(plan.text == "Вихід")
        #expect(plan.targetLanguage == "en")
    }
    @Test func typedResultReachesNativeStateWithoutDiagnosticsContent() {
        let model = AssistantViewModel()
        let result = TranslationProductionResult(sourceText: "private-source", translatedText: "private-target", sourceLanguage: "uk", targetLanguage: "en")
        model.handleTranslationResult(result)
        #expect(model.resultState == .translation(result))
        #expect(!model.voiceDiagnosticReport().contains("private-source"))
        #expect(!model.voiceDiagnosticReport().contains("private-target"))
    }

    @Test func followUpRetranslatesOriginalSourceInsteadOfPreviousTranslation() {
        let model = AssistantViewModel()
        model.handleTranslationResult(.init(sourceText: "Добрий вечір, як справи?", translatedText: "Good evening, how are you?", sourceLanguage: "uk", targetLanguage: "en"))
        model.input = "А тепер німецькою"
        model.submit()
        guard case let .translation(plan) = model.capabilityPresentation else { Issue.record("Expected translation continuation"); return }
        #expect(plan.text == "Добрий вечір, як справи?")
        #expect(plan.targetLanguage == "de")
    }

    @Test func morphologyAndVoiceVariantsReachTheCanonicalAppleTranslationBoundary() async throws {
        let engine = LocalCommandEngine()
        let ukrainian = engine.parse("Будь ласка, перекласти німецькою мовою: Гарного ранку")
        #expect(ukrainian.intent == .translation)
        #expect(ukrainian.entities["target_language"] == "de")
        #expect(ukrainian.entities["source_text"] == "Гарного ранку")
        let russian = engine.parse("Перевести на английский, До встречи завтра")
        #expect(russian.intent == .translation)
        #expect(russian.entities["target_language"] == "en")
        #expect(russian.entities["source_text"] == "До встречи завтра")

        let executor = ProductionCanonicalCapabilityExecutor()
        guard case let .presentation(.translation(plan)) = try await executor.execute(ukrainian) else {
            Issue.record("Expected canonical Apple Translation presentation")
            return
        }
        #expect(plan.text == "Гарного ранку")
        #expect(plan.targetLanguage == "de")
    }
}
