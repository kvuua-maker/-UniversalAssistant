import Testing
import Vision
@testable import UniversalAssistant

@Suite("Production QR and barcode")
@MainActor
struct ProductionScannerTests {
    @Test func productionRequestPresentsRealScanner() async throws {
        let command = LocalCommandEngine().parse("Скануй QR-код")
        #expect(command.intent == .cameraCapture)
        #expect(command.entities["capture_mode"] == "code_scan")
        #expect(try await ProductionCanonicalCapabilityExecutor(personalSearchSources: []).execute(command) == .presentation(.scanner))
    }

    @Test func callbackCreatesTypedObservedQRResult() throws {
        let result = try ScannerProductionRouter().route(.init(payload: "https://example.com/item", symbology: .qr))
        #expect(result.observedValue == "https://example.com/item")
        #expect(result.observedType == "qr")
        #expect(result.route.action == .open)
        #expect(result.route.requiresConfirmation)
    }

    @Test func viewModelOwnsTypedScannerResult() {
        let model = AssistantViewModel(compactResultDuration: .seconds(60))
        model.handleScannedCode(.init(payload: "local note", symbology: .qr))
        guard case let .scanner(result) = model.resultState else { Issue.record("Expected scanner result"); return }
        #expect(result.observedValue == "local note")
        #expect(result.route.action == .save)
    }

    @Test func validBarcodeUsesValidatedGTINAndInvalidBarcodeFails() throws {
        let valid = try ScannerProductionRouter().route(.init(payload: "4006381333931", symbology: .ean13))
        #expect(valid.observedType == "barcode")
        #expect(valid.route.action == .identifyProduct)
        #expect(throws: SharedContentRoutingError.invalidPayload) {
            try ScannerProductionRouter().route(.init(payload: "4006381333932", symbology: .ean13))
        }
    }

    @Test func sensitiveKindsRequireConfirmation() throws {
        for payload in ["https://example.com", "WIFI:T:WPA;S:network;P:secret;;", "mailto:owner@example.com", "tel:+380501234567", "BEGIN:VCARD\nVERSION:3.0\nFN:Owner\nEND:VCARD"] {
            #expect(try ScannerProductionRouter().route(.init(payload: payload, symbology: .qr)).route.requiresConfirmation)
        }
    }

    @Test func paymentAndUnknownSchemesAreTruthfullyUnsupported() {
        for payload in ["bitcoin:abc", "custom:opaque"] {
            #expect(throws: SharedContentRoutingError.unsupportedAction) {
                try ScannerProductionRouter().route(.init(payload: payload, symbology: .qr))
            }
        }
    }

    @Test func actionLabelsDescribeTheSafeConcreteContinuation() throws {
        #expect(try ScannerProductionRouter().route(.init(payload: "https://example.com", symbology: .qr)).actionTitle == "Відкрити")
        #expect(try ScannerProductionRouter().route(.init(payload: "plain text", symbology: .qr)).actionTitle == "Копіювати")
        #expect(try ScannerProductionRouter().route(.init(payload: "4006381333931", symbology: .ean13)).actionTitle == "Знайти товар")
    }

    @Test func retailBarcodeActionUsesTruthfulProductHandoff() throws {
        let model = AssistantViewModel(compactResultDuration: .seconds(60))
        let result = try ScannerProductionRouter().route(.init(payload: "4006381333931", symbology: .ean13))
        model.performScannerAction(result)
        guard case let .webHandoff(handoff) = model.resultState else { Issue.record("Expected product handoff"); return }
        #expect(handoff.query == "GTIN 4006381333931")
        #expect(handoff.destination.scheme == "https")
    }

    @Test func plainQRUsesExplicitSafeCopyAction() throws {
        let result = try ScannerProductionRouter().route(.init(payload: "inventory note", symbology: .qr))
        #expect(result.route.action == .save)
        #expect(!result.route.requiresConfirmation)
    }
}
