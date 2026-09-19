import Foundation
import UIKit
import SwiftUI
import Vision
@preconcurrency import VisionKit

@MainActor
final class LiveCodeScanner: NSObject, DataScannerViewControllerDelegate {
    var onPayload: ((ObservedScannerCode) -> Void)?

    func makeController() throws -> DataScannerViewController {
        guard DataScannerViewController.isSupported else {
            throw SharedContentRoutingError.unsupportedAction
        }
        return DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr, .ean13, .ean8, .upce, .code128])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
    }

    func dataScanner(
        _ dataScanner: DataScannerViewController,
        didAdd addedItems: [RecognizedItem],
        allItems: [RecognizedItem]
    ) {
        for item in addedItems {
            guard case let .barcode(barcode) = item,
                  let payload = barcode.payloadStringValue else { continue }
            onPayload?(ObservedScannerCode(payload: payload, symbology: barcode.observation.symbology))
            dataScanner.stopScanning()
            return
        }
    }
}

struct ObservedScannerCode: Equatable, Sendable {
    let payload: String
    let symbology: VNBarcodeSymbology
    var isQR: Bool { symbology == .qr }
}

struct ScannerProductionResult: Equatable, Sendable {
    let observedValue: String
    let observedType: String
    let route: SharedContentRoute

    var actionTitle: String {
        switch route.action {
        case .open: "Відкрити"
        case .call: "Зателефонувати"
        case .importContact: "Імпортувати контакт"
        case .identifyProduct: "Знайти товар"
        case .save: "Копіювати"
        default: "Продовжити"
        }
    }
}

struct ScannerProductionRouter: Sendable {
    private let router = SharedContentActionRouter()
    func route(_ observation: ObservedScannerCode) throws -> ScannerProductionResult {
        let route = try observation.isQR ? router.routeQR(observation.payload) : router.routeRetailBarcode(observation.payload)
        return .init(observedValue: observation.payload.trimmingCharacters(in: .whitespacesAndNewlines), observedType: observation.isQR ? "qr" : "barcode", route: route)
    }
}

@MainActor
struct LiveCodeScannerView: UIViewControllerRepresentable {
    let onResult: (ObservedScannerCode) -> Void
    let onUnavailable: () -> Void
    func makeCoordinator() -> LiveCodeScanner { let scanner = LiveCodeScanner(); scanner.onPayload = onResult; return scanner }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        do { let controller = try context.coordinator.makeController(); controller.delegate = context.coordinator; try controller.startScanning(); return controller }
        catch { Task { @MainActor in onUnavailable() }; return DataScannerViewController(recognizedDataTypes: [.barcode()], qualityLevel: .balanced, recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false, isPinchToZoomEnabled: false, isGuidanceEnabled: false, isHighlightingEnabled: false) }
    }
    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}
}

@MainActor
struct SystemDocumentScannerView: UIViewControllerRepresentable {
    let onPages: ([UIImage]) -> Void
    let onFailure: (Error) -> Void

    func makeCoordinator() -> DocumentScannerCoordinator {
        let coordinator = DocumentScannerCoordinator()
        coordinator.onPages = onPages
        coordinator.onFailure = onFailure
        return coordinator
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        context.coordinator.makeController()
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}
}

@MainActor
final class DocumentScannerCoordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
    var onPages: (([UIImage]) -> Void)?
    var onFailure: ((Error) -> Void)?

    func makeController() -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = self
        return controller
    }

    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFinishWith scan: VNDocumentCameraScan
    ) {
        let pages = (0..<scan.pageCount).map(scan.imageOfPage(at:))
        controller.dismiss(animated: true)
        onPages?(pages)
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        controller.dismiss(animated: true)
    }

    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFailWithError error: Error
    ) {
        controller.dismiss(animated: true)
        onFailure?(error)
    }
}


@MainActor
protocol DocumentOCRProcessing: AnyObject {
    func recognize(cgImage: CGImage) async throws -> [String]
}

enum OCRInputProvenance: String, Equatable, Sendable { case camera, document, sharedImage, photoLibrary }
enum OCRResultAction: String, CaseIterable, Equatable, Sendable { case copy, share, translate }
struct OCRProductionResult: Equatable, Sendable {
    let recognizedText: String
    let provenance: OCRInputProvenance
    let actions: [OCRResultAction]
}
enum OCRProductionError: Error, Equatable { case cancelled, unsupportedInput, noTextDetected, processingFailed }


@MainActor
final class OnDeviceDocumentOCR: DocumentOCRProcessing {
    func recognize(cgImage: CGImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let lines = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string } ?? []
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            if let supported = try? request.supportedRecognitionLanguages() {
                let preferred = ["uk-UA", "en-US", "ru-RU"]
                request.recognitionLanguages = preferred.filter(supported.contains)
            }
            do { try VNImageRequestHandler(cgImage: cgImage).perform([request]) }
            catch { continuation.resume(throwing: error) }
        }
    }
}


@MainActor
struct OCRProductionPipeline {
    let processor: any DocumentOCRProcessing
    init(processor: any DocumentOCRProcessing = OnDeviceDocumentOCR()) { self.processor = processor }
    func process(_ image: UIImage?, provenance: OCRInputProvenance) async throws -> OCRProductionResult {
        guard let image else { throw OCRProductionError.cancelled }
        guard let cgImage = image.cgImage else { throw OCRProductionError.unsupportedInput }
        let lines: [String]
        do { lines = try await processor.recognize(cgImage: cgImage) }
        catch { throw OCRProductionError.processingFailed }
        let text = lines.map { line in line.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { line in !line.isEmpty }.joined(separator: "\n")
        guard !text.isEmpty else { throw OCRProductionError.noTextDetected }
        return .init(recognizedText: text, provenance: provenance, actions: OCRResultAction.allCases)
    }

    func process(_ images: [UIImage], provenance: OCRInputProvenance) async throws -> OCRProductionResult {
        guard !images.isEmpty else { throw OCRProductionError.cancelled }
        var pages: [String] = []
        for image in images {
            try Task.checkCancellation()
            let page = try await process(image, provenance: provenance).recognizedText
            pages.append(page)
        }
        return .init(recognizedText: pages.joined(separator: "\n\n"), provenance: provenance, actions: OCRResultAction.allCases)
    }
}
