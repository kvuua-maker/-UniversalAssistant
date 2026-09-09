import Foundation
import PDFKit
import Testing
import UIKit
@testable import UniversalAssistant

@Suite("On-device PDF processing") @MainActor
struct OnDevicePDFProcessorTests {
    private func pdf(_ labels: [String]) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        return UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 200), format: format).pdfData { context in
            for label in labels {
                context.beginPage()
                (label as NSString).draw(at: CGPoint(x: 20, y: 20), withAttributes: [.font: UIFont.systemFont(ofSize: 16)])
            }
        }
    }

    private func strings(_ data: Data) throws -> [String] {
        let document = try #require(PDFDocument(data: data))
        return (0..<document.pageCount).map { document.page(at: $0)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    }

    @Test func mergeReorderDeleteAndSplitOperateOnActualPDFBytes() throws {
        let processor = OnDevicePDFProcessor()
        let merged = try processor.merge([pdf(["A", "B"]), pdf(["C"])])
        #expect(try strings(merged) == ["A", "B", "C"])
        let reordered = try processor.reordered(merged, pageOrder: [2, 0, 1])
        #expect(try strings(reordered) == ["C", "A", "B"])
        let deleted = try processor.deleting([1], from: reordered)
        #expect(try strings(deleted) == ["C", "B"])
        let split = try processor.split(merged, groups: [[0, 2], [1]])
        #expect(try strings(split[0]) == ["A", "C"])
        #expect(try strings(split[1]) == ["B"])
    }

    @Test func rotationIsExplicitAndInvalidDestructiveSelectionsFailClosed() throws {
        let processor = OnDevicePDFProcessor()
        let source = pdf(["A", "B"])
        let rotated = try processor.rotating([0], degreesClockwise: 90, in: source)
        let document = try #require(PDFDocument(data: rotated))
        #expect(document.page(at: 0)?.rotation == 90)
        #expect(document.page(at: 1)?.rotation == 0)
        #expect(throws: PDFProcessingError.invalidPageSelection) { try processor.deleting([0, 1], from: source) }
        #expect(throws: PDFProcessingError.duplicatePageSelection) { try processor.reordered(source, pageOrder: [0, 0]) }
    }

    @Test func imagePDFIsSearchableAndCompressionProducesValidRasterizedPages() throws {
        let processor = OnDevicePDFProcessor()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
            UIColor.blue.setFill(); context.fill(CGRect(x: 20, y: 20, width: 100, height: 100))
        }
        let searchable = try processor.searchablePDF(images: [image], recognizedText: ["Invoice 2026 ACME"])
        let searchableDocument = try #require(PDFDocument(data: searchable))
        #expect(searchableDocument.page(at: 0)?.string?.contains("Invoice 2026 ACME") == true)
        let compressed = try processor.compressed(pdf(["high resolution source"]), maximumDimension: 600, jpegQuality: 0.5)
        #expect(try #require(PDFDocument(data: compressed)).pageCount == 1)
    }

    @Test func redactionAndSignatureAreFlattenedAndInvalidOverlaysFailClosed() throws {
        let processor = OnDevicePDFProcessor()
        let signature = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 30)).image { context in
            UIColor.clear.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 30))
            UIColor.red.setStroke(); context.cgContext.setLineWidth(3)
            context.cgContext.move(to: CGPoint(x: 4, y: 20)); context.cgContext.addLine(to: CGPoint(x: 96, y: 8)); context.cgContext.strokePath()
        }
        let overlays = [
            PDFPageOverlay(pageIndex: 0, normalizedRect: CGRect(x: 0.05, y: 0.05, width: 0.4, height: 0.15), kind: .redaction),
            PDFPageOverlay(pageIndex: 0, normalizedRect: CGRect(x: 0.5, y: 0.7, width: 0.4, height: 0.15), kind: .signature)
        ]
        let flattened = try processor.flattened(pdf(["secret value"]), overlays: overlays, signature: signature)
        let document = try #require(PDFDocument(data: flattened))
        #expect(document.pageCount == 1)
        #expect(document.page(at: 0)?.annotations.isEmpty == true)
        #expect(document.page(at: 0)?.string?.contains("secret value") != true)
        #expect(throws: PDFProcessingError.invalidOverlay) {
            try processor.flattened(pdf(["A"]), overlays: [PDFPageOverlay(pageIndex: 2, normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1), kind: .redaction)])
        }
    }

    @Test func cropEnhancePDFImageAndHighlightOperateOnRealContent() throws {
        let processor = OnDevicePDFProcessor()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 200)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
            UIColor.gray.setFill(); context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        }
        let cropped = try processor.cropped(image, normalizedRect: CGRect(x: 0, y: 0, width: 0.5, height: 1))
        #expect(cropped.size.width == image.size.width / 2)
        #expect(try processor.contrastEnhanced(cropped).size == cropped.size)
        let pageImages = try processor.images(from: pdf(["Pay by Monday"]))
        #expect(pageImages.count == 1)
        #expect(pageImages[0].size.width > 0)
        let highlighted = try processor.highlighting("Monday", in: pdf(["Pay by Monday"]))
        let document = try #require(PDFDocument(data: highlighted))
        #expect(document.page(at: 0)?.annotations.contains(where: { $0.type == "Highlight" }) == true)
        #expect(throws: PDFProcessingError.invalidPageSelection) {
            try processor.highlighting("not present", in: pdf(["Pay by Monday"]))
        }
    }

    @Test func textRedactionFlattensMatchedContentAndMissingMatchFailsClosed() throws {
        let processor = OnDevicePDFProcessor()
        let redacted = try processor.redacting("account 7788", in: pdf(["private account 7788 value"]))
        let document = try #require(PDFDocument(data: redacted))
        #expect(document.page(at: 0)?.annotations.isEmpty == true)
        #expect(document.page(at: 0)?.string?.contains("7788") != true)
        #expect(throws: PDFProcessingError.invalidOverlay) { try processor.redacting("absent", in: pdf(["public"])) }
    }
}
