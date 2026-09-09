import Foundation
import PDFKit
import UIKit
import CoreImage

enum PDFProcessingError: Error, Equatable {
    case invalidPDF, emptyDocument, invalidPageSelection, duplicatePageSelection, invalidOverlay
}

struct PDFPageOverlay: Sendable, Equatable {
    enum Kind: Sendable, Equatable { case redaction, signature }
    let pageIndex: Int
    let normalizedRect: CGRect
    let kind: Kind
}

@MainActor
struct OnDevicePDFProcessor {
    func pageCount(_ data: Data) throws -> Int { try document(data).pageCount }
    func merge(_ documents: [Data]) throws -> Data {
        guard !documents.isEmpty else { throw PDFProcessingError.emptyDocument }
        let output = PDFDocument()
        for data in documents {
            guard let source = PDFDocument(data: data), source.pageCount > 0 else { throw PDFProcessingError.invalidPDF }
            for index in 0..<source.pageCount {
                guard let page = source.page(at: index)?.copy() as? PDFPage else { throw PDFProcessingError.invalidPDF }
                output.insert(page, at: output.pageCount)
            }
        }
        return try representation(of: output)
    }

    func reordered(_ data: Data, pageOrder: [Int]) throws -> Data {
        let source = try document(data)
        guard pageOrder.count == source.pageCount,
              Set(pageOrder).count == pageOrder.count else { throw PDFProcessingError.duplicatePageSelection }
        guard pageOrder.allSatisfy({ source.page(at: $0) != nil }) else { throw PDFProcessingError.invalidPageSelection }
        return try build(from: source, indexes: pageOrder)
    }

    func deleting(_ indexes: Set<Int>, from data: Data) throws -> Data {
        let source = try document(data)
        guard !indexes.isEmpty, indexes.allSatisfy({ source.page(at: $0) != nil }),
              indexes.count < source.pageCount else { throw PDFProcessingError.invalidPageSelection }
        return try build(from: source, indexes: (0..<source.pageCount).filter { !indexes.contains($0) })
    }

    func split(_ data: Data, groups: [[Int]]) throws -> [Data] {
        let source = try document(data)
        guard !groups.isEmpty, groups.allSatisfy({ !$0.isEmpty }),
              groups.flatMap({ $0 }).allSatisfy({ source.page(at: $0) != nil }) else {
            throw PDFProcessingError.invalidPageSelection
        }
        return try groups.map { try build(from: source, indexes: $0) }
    }

    func rotating(_ indexes: Set<Int>, degreesClockwise: Int, in data: Data) throws -> Data {
        let source = try document(data)
        guard [90, 180, 270].contains(degreesClockwise),
              !indexes.isEmpty, indexes.allSatisfy({ source.page(at: $0) != nil }) else {
            throw PDFProcessingError.invalidPageSelection
        }
        let output = PDFDocument()
        for index in 0..<source.pageCount {
            guard let page = source.page(at: index)?.copy() as? PDFPage else { throw PDFProcessingError.invalidPDF }
            if indexes.contains(index) { page.rotation = (page.rotation + degreesClockwise) % 360 }
            output.insert(page, at: output.pageCount)
        }
        return try representation(of: output)
    }

    func searchablePDF(images: [UIImage], recognizedText: [String]) throws -> Data {
        guard !images.isEmpty, images.count == recognizedText.count else { throw PDFProcessingError.emptyDocument }
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            for (image, text) in zip(images, recognizedText) {
                context.beginPage()
                image.draw(in: bounds)
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byWordWrapping
                (text as NSString).draw(
                    in: bounds.insetBy(dx: 24, dy: 24),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 1), .foregroundColor: UIColor(white: 0, alpha: 0.01), .paragraphStyle: paragraph]
                )
            }
        }
    }

    func cropped(_ image: UIImage, normalizedRect: CGRect) throws -> UIImage {
        guard normalizedRect.minX >= 0, normalizedRect.minY >= 0,
              normalizedRect.maxX <= 1, normalizedRect.maxY <= 1,
              normalizedRect.width > 0, normalizedRect.height > 0,
              let cgImage = image.cgImage else { throw PDFProcessingError.invalidPageSelection }
        let pixels = CGRect(x: normalizedRect.minX * CGFloat(cgImage.width),
                            y: normalizedRect.minY * CGFloat(cgImage.height),
                            width: normalizedRect.width * CGFloat(cgImage.width),
                            height: normalizedRect.height * CGFloat(cgImage.height)).integral
        guard let cropped = cgImage.cropping(to: pixels) else { throw PDFProcessingError.invalidPageSelection }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    func contrastEnhanced(_ image: UIImage, amount: CGFloat = 1.15) throws -> UIImage {
        guard (1...1.5).contains(amount), let input = CIImage(image: image) else { throw PDFProcessingError.invalidPageSelection }
        let filter = CIFilter(name: "CIColorControls")
        filter?.setValue(input, forKey: kCIInputImageKey)
        filter?.setValue(amount, forKey: kCIInputContrastKey)
        guard let output = filter?.outputImage,
              let cgImage = CIContext(options: [.useSoftwareRenderer: false]).createCGImage(output, from: output.extent) else {
            throw PDFProcessingError.invalidPDF
        }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }

    func images(from data: Data, maximumDimension: CGFloat = 2_048) throws -> [UIImage] {
        let source = try document(data)
        guard maximumDimension >= 320 else { throw PDFProcessingError.invalidPageSelection }
        return try (0..<source.pageCount).map { index in
            guard let page = source.page(at: index) else { throw PDFProcessingError.invalidPDF }
            let box = page.bounds(for: .mediaBox)
            let scale = min(1, maximumDimension / max(box.width, box.height))
            return UIGraphicsImageRenderer(size: CGSize(width: box.width * scale, height: box.height * scale)).image { context in
                UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: context.format.bounds.size))
                context.cgContext.scaleBy(x: scale, y: scale)
                page.draw(with: .mediaBox, to: context.cgContext)
            }
        }
    }

    func highlighting(_ text: String, in data: Data) throws -> Data {
        let output = try document(data)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PDFProcessingError.invalidPageSelection }
        let selections = output.findString(text, withOptions: [.caseInsensitive])
        guard !selections.isEmpty else { throw PDFProcessingError.invalidPageSelection }
        for selection in selections {
            for page in selection.pages {
                let bounds = selection.bounds(for: page)
                let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                annotation.color = UIColor.systemYellow.withAlphaComponent(0.35)
                page.addAnnotation(annotation)
            }
        }
        return try representation(of: output)
    }

    func redacting(_ text: String, in data: Data) throws -> Data {
        let source = try document(data)
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw PDFProcessingError.invalidOverlay }
        let selections = source.findString(query, withOptions: [.caseInsensitive])
        guard !selections.isEmpty else { throw PDFProcessingError.invalidOverlay }
        var overlays: [PDFPageOverlay] = []
        for selection in selections {
            for page in selection.pages {
                let pageIndex = source.index(for: page)
                let box = page.bounds(for: .mediaBox)
                let rect = selection.bounds(for: page)
                guard pageIndex >= 0, box.width > 0, box.height > 0 else { continue }
                overlays.append(.init(pageIndex: pageIndex, normalizedRect: .init(
                    x: (rect.minX - box.minX) / box.width,
                    y: (rect.minY - box.minY) / box.height,
                    width: rect.width / box.width,
                    height: rect.height / box.height
                ), kind: .redaction))
            }
        }
        guard !overlays.isEmpty else { throw PDFProcessingError.invalidOverlay }
        return try flattened(data, overlays: overlays)
    }

    func compressed(_ data: Data, maximumDimension: CGFloat = 1_600, jpegQuality: CGFloat = 0.72) throws -> Data {
        let source = try document(data)
        guard maximumDimension >= 320, (0.1...1).contains(jpegQuality) else { throw PDFProcessingError.invalidPageSelection }
        let output = PDFDocument()
        for index in 0..<source.pageCount {
            guard let page = source.page(at: index) else { throw PDFProcessingError.invalidPDF }
            let box = page.bounds(for: .mediaBox)
            let scale = min(1, maximumDimension / max(box.width, box.height))
            let size = CGSize(width: max(1, box.width * scale), height: max(1, box.height * scale))
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { context in
                UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
                context.cgContext.saveGState()
                context.cgContext.scaleBy(x: scale, y: scale)
                page.draw(with: .mediaBox, to: context.cgContext)
                context.cgContext.restoreGState()
            }
            guard let jpeg = image.jpegData(compressionQuality: jpegQuality),
                  let compressedImage = UIImage(data: jpeg),
                  let compressedPage = PDFPage(image: compressedImage) else { throw PDFProcessingError.invalidPDF }
            output.insert(compressedPage, at: output.pageCount)
        }
        return try representation(of: output)
    }

    /// Destructive overlays are flattened into page pixels so removed content cannot be recovered
    /// by deleting a PDF annotation. Signature pixels are supplied explicitly by the user.
    func flattened(_ data: Data, overlays: [PDFPageOverlay], signature: UIImage? = nil) throws -> Data {
        let source = try document(data)
        guard !overlays.isEmpty else { throw PDFProcessingError.invalidOverlay }
        guard overlays.allSatisfy({ overlay in
            source.page(at: overlay.pageIndex) != nil && overlay.normalizedRect.minX >= 0 && overlay.normalizedRect.minY >= 0 &&
            overlay.normalizedRect.maxX <= 1 && overlay.normalizedRect.maxY <= 1 && overlay.normalizedRect.width > 0 && overlay.normalizedRect.height > 0 &&
            (overlay.kind != .signature || signature != nil)
        }) else { throw PDFProcessingError.invalidOverlay }

        let output = PDFDocument()
        for index in 0..<source.pageCount {
            guard let page = source.page(at: index) else { throw PDFProcessingError.invalidPDF }
            let box = page.bounds(for: .mediaBox)
            let renderer = UIGraphicsImageRenderer(size: box.size)
            let image = renderer.image { context in
                UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: box.size))
                page.draw(with: .mediaBox, to: context.cgContext)
                for overlay in overlays where overlay.pageIndex == index {
                    let rect = CGRect(x: overlay.normalizedRect.minX * box.width,
                                      y: overlay.normalizedRect.minY * box.height,
                                      width: overlay.normalizedRect.width * box.width,
                                      height: overlay.normalizedRect.height * box.height)
                    switch overlay.kind {
                    case .redaction: UIColor.black.setFill(); context.fill(rect)
                    case .signature: signature?.draw(in: rect)
                    }
                }
            }
            guard let flattenedPage = PDFPage(image: image) else { throw PDFProcessingError.invalidPDF }
            output.insert(flattenedPage, at: output.pageCount)
        }
        return try representation(of: output)
    }

    private func document(_ data: Data) throws -> PDFDocument {
        guard let document = PDFDocument(data: data), document.pageCount > 0 else { throw PDFProcessingError.invalidPDF }
        return document
    }

    private func build(from source: PDFDocument, indexes: [Int]) throws -> Data {
        let output = PDFDocument()
        for index in indexes {
            guard let page = source.page(at: index)?.copy() as? PDFPage else { throw PDFProcessingError.invalidPDF }
            output.insert(page, at: output.pageCount)
        }
        return try representation(of: output)
    }

    private func representation(of document: PDFDocument) throws -> Data {
        guard document.pageCount > 0, let data = document.dataRepresentation() else { throw PDFProcessingError.emptyDocument }
        return data
    }
}
