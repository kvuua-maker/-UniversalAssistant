import Foundation
import UIKit
import Vision
@preconcurrency import VisionKit

@MainActor
final class LiveCodeScanner: NSObject, DataScannerViewControllerDelegate {
    var onPayload: ((String) -> Void)?

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
            onPayload?(payload)
            dataScanner.stopScanning()
            return
        }
    }
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
