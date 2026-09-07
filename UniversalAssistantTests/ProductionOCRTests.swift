import Testing
import UIKit
@testable import UniversalAssistant

@Suite("Production OCR")
@MainActor
struct ProductionOCRTests {
    @Test func cameraAndAuthorizedDocumentRequestsReachOCRPresentation() async throws {
        let camera = LocalCommandEngine().parse("Розпізнай текст")
        #expect(camera.entities["capture_mode"] == "text_scan")
        #expect(try await ProductionCanonicalCapabilityExecutor(personalSearchSources: []).execute(camera) == .presentation(.ocrCamera))
        let document = LocalCommandEngine().parse("Розпізнай текст у документі")
        #expect(document.entities["input_source"] == "document")
        #expect(try await ProductionCanonicalCapabilityExecutor(personalSearchSources: []).execute(document) == .presentation(.ocrDocuments))
    }

    @Test func observedTextProducesTypedLocalResultAndActions() async throws {
        let processor = OCRProcessorStub(.success([" First line ", "Second line"]))
        let result = try await OCRProductionPipeline(processor: processor).process(image(), provenance: .camera)
        #expect(result.recognizedText == "First line\nSecond line")
        #expect(result.provenance == .camera)
        #expect(result.actions == [.copy, .share, .translate])
        #expect(processor.callCount == 1)
    }

    @Test func selectedImageUsesSameProductionPipeline() async throws {
        let result = try await OCRProductionPipeline(processor: OCRProcessorStub(.success(["Document text"]))).process(image(), provenance: .document)
        #expect(result.provenance == .document)
        #expect(result.recognizedText == "Document text")
    }

    @Test func noTextIsTruthful() async {
        await #expect(throws: OCRProductionError.noTextDetected) { try await OCRProductionPipeline(processor: OCRProcessorStub(.success(["  "]))).process(image(), provenance: .camera) }
    }

    @Test func cancellationAndUnsupportedInputAreTruthful() async {
        await #expect(throws: OCRProductionError.cancelled) { try await OCRProductionPipeline(processor: OCRProcessorStub(.success([]))).process(nil, provenance: .camera) }
        await #expect(throws: OCRProductionError.unsupportedInput) { try await OCRProductionPipeline(processor: OCRProcessorStub(.success([]))).process(UIImage(), provenance: .camera) }
    }

    @Test func processingFailureIsTruthful() async {
        await #expect(throws: OCRProductionError.processingFailed) { try await OCRProductionPipeline(processor: OCRProcessorStub(.failure(TestFailure()))).process(image(), provenance: .camera) }
    }

    @Test func viewModelClearsTransientPresentationAndOwnsTypedResult() async throws {
        let model = AssistantViewModel(ocrProcessor: OCRProcessorStub(.success(["private-observed-value"])), compactResultDuration: .seconds(60))
        model.handleCapturedOCRImage(image())
        try await waitUntil { if case .ocr = model.resultState { true } else { false } }
        #expect(model.capabilityPresentation == nil)
        guard case let .ocr(result) = model.resultState else { return }
        #expect(result.recognizedText == "private-observed-value")
        #expect(!model.voiceDiagnosticReport().contains("private-observed-value"))
    }

    @Test func cancellationClearsTransientStateAndFailsTruthfully() {
        let model = AssistantViewModel(ocrProcessor: OCRProcessorStub(.success([])))
        model.handleCapturedOCRImage(nil)
        #expect(model.capabilityPresentation == nil)
        if case .failure = model.resultState {} else { Issue.record("Expected truthful cancellation failure") }
    }

    @Test func translationIsAContinuationContractNotAutomaticExecution() async throws {
        let result = try await OCRProductionPipeline(processor: OCRProcessorStub(.success(["Вихід"]))).process(image(), provenance: .camera)
        #expect(result.actions.contains(.translate))
        let model = AssistantViewModel(ocrProcessor: OCRProcessorStub(.success([])))
        model.performOCRAction(result, .translate)
        #expect(model.input == "Вихід")
        if case .actionRequired = model.resultState {} else { Issue.record("Expected target-language clarification") }
    }

    @Test func sharedImageFollowUpUsesPreservedPayloadAndLocalOCR() async throws {
        let model = AssistantViewModel(ocrProcessor: OCRProcessorStub(.success(["Shared image text"])), compactResultDuration: .seconds(60))
        let encoded = try #require(image().jpegData(compressionQuality: 0.9)).base64EncodedString()
        model.ingestShared(.init(kind: "image", value: encoded, receivedAt: .now))
        model.input = "Що написано на цій фотографії?"
        model.submit()
        try await waitUntil { if case .ocr = model.resultState { true } else { false } }
        guard case let .ocr(result) = model.resultState else { return }
        #expect(result.recognizedText == "Shared image text")
        #expect(result.provenance == .sharedImage)
    }

    @Test func publicDocumentScanUsesVisionKitAndProcessesEveryPage() async throws {
        let command = LocalCommandEngine().parse("Відскануй документ")
        #expect(command.intent == .cameraCapture)
        #expect(command.entities["capture_mode"] == "text_scan")
        #expect(command.entities["input_source"] == "document_camera")
        #expect(try await ProductionCanonicalCapabilityExecutor(personalSearchSources: []).execute(command) == .presentation(.scanDocument))

        let processor = OCRProcessorStub(.success(["Page text"]))
        let result = try await OCRProductionPipeline(processor: processor).process([image(), image()], provenance: .document)
        #expect(result.recognizedText == "Page text\n\nPage text")
        #expect(processor.callCount == 2)
    }

    @Test("Document scan semantic variants", arguments: ["Скануй документ", "Сканируй документ", "Scan document"])
    func documentScanVariantsConverge(_ phrase: String) async throws {
        let command = LocalCommandEngine().parse(phrase)
        #expect(command.intent == .cameraCapture)
        #expect(command.entities["input_source"] == "document_camera")
        #expect(try await ProductionCanonicalCapabilityExecutor(personalSearchSources: []).execute(command) == .presentation(.scanDocument))
    }

    @Test func scannedPagesReachTypedOCRResultAtProductionBoundary() async throws {
        let model = AssistantViewModel(ocrProcessor: OCRProcessorStub(.success(["Complete receipt line"])), compactResultDuration: .seconds(60))
        model.handleScannedOCRDocument([image(), image()])
        try await waitUntil { if case .ocr = model.resultState { true } else { false } }
        guard case let .ocr(result) = model.resultState else { return }
        #expect(result.provenance == .document)
        #expect(result.recognizedText == "Complete receipt line\n\nComplete receipt line")
        #expect(result.actions == [.copy, .share, .translate])
    }

    private func image() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 4, height: 4)) }
    }
    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<100 { if condition() { return }; try await Task.sleep(for: .milliseconds(10)) }
        Issue.record("Timed out waiting for OCR result")
    }
}

@MainActor
private final class OCRProcessorStub: DocumentOCRProcessing {
    let result: Result<[String], Error>
    private(set) var callCount = 0
    init(_ result: Result<[String], Error>) { self.result = result }
    func recognize(cgImage: CGImage) async throws -> [String] { callCount += 1; return try result.get() }
}
private struct TestFailure: Error {}
