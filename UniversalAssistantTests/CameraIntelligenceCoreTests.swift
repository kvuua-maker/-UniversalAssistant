import Testing
@testable import UniversalAssistant

@Suite("Privacy-safe camera intelligence")
struct CameraIntelligenceCoreTests {
    private let core = CameraIntelligenceCore()

    @Test func paymentAndURLQRNeverAutoExecute() throws {
        let payment = try core.assessQR("bitcoin:bc1qexample?amount=1")
        #expect(payment.kind == .payment)
        #expect(payment.requiresConfirmation)
        #expect(!payment.mayAutoExecute)
        let url = try core.assessQR("https://example.com/pay")
        #expect(url.kind == .webURL)
        #expect(url.requiresConfirmation)
        #expect(!url.mayAutoExecute)
    }

    @Test func validGTINIsExactButVisualLabelIsOnlyProbable() throws {
        #expect(try core.productEvidence(barcode: "0194253406532", visualLabel: nil, confidence: nil) == .exactGTIN("0194253406532"))
        let visual = try core.productEvidence(barcode: "0194253406533", visualLabel: "black smartphone", confidence: 0.92)
        #expect(visual == .probableVisualSimilarity(label: "black smartphone", confidence: 0.92))
    }

    @Test func weakVisualEvidenceIsInsufficient() throws {
        #expect(try core.productEvidence(barcode: nil, visualLabel: "bottle", confidence: 0.2) == .insufficient)
    }

    @Test func translationUsesSystemFirstAndNarratesOnlyWhenAsked() throws {
        let silent = try core.translationPlan(text: " Вихід ", sourceLanguage: "uk", targetLanguage: "de")
        #expect(silent.usesLocalOrSystemFramework)
        #expect(!silent.narrate)
        #expect(try core.translationPlan(text: "Вихід", sourceLanguage: "uk", targetLanguage: "de", readAloud: true).narrate)
    }
}
