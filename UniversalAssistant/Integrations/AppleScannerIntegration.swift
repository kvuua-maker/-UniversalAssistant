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

struct OnDeviceDocumentOCR {
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
            do { try VNImageRequestHandler(cgImage: cgImage).perform([request]) }
            catch { continuation.resume(throwing: error) }
        }
    }
}
