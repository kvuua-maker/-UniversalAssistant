import Foundation
import PDFKit
import UIKit
import Vision

/// PDF operations used by the PDF Tools screen. Every method is async and does
/// its heavy work off the main actor; results are returned as URLs in a
/// temporary directory so the caller can preview, share, print or save them.
actor PDFToolsEngine {
    static let shared = PDFToolsEngine()

    private var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("PDFTools", isDirectory: true)
    }

    private func freshURL(_ name: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        return url
    }

    // MARK: - Create

    func makePDF(from images: [UIImage], name: String = "images.pdf") throws -> URL {
        let url = try freshURL(name)
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 at 72 dpi
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        try renderer.writePDF(to: url) { context in
            for image in images {
                context.beginPage()
                let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let origin = CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
                image.draw(in: CGRect(origin: origin, size: size))
            }
        }
        let kb = fileSizeKB(url)
        Task { @MainActor in RuntimeDiagnostics.shared.log("PDF", "created \(images.count) pages, size = \(kb) KB") }
        return url
    }

    func makeBlankPDF(pages: Int = 1, name: String = "blank.pdf") throws -> URL {
        let url = try freshURL(name)
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        try renderer.writePDF(to: url) { context in
            for _ in 0..<max(1, pages) { context.beginPage() }
        }
        let count = max(1, pages)
        Task { @MainActor in RuntimeDiagnostics.shared.log("PDF", "created blank PDF, \(count) pages") }
        return url
    }

    // MARK: - Combine / split

    func merge(_ urls: [URL], name: String = "merged.pdf") throws -> URL {
        let output = PDFDocument()
        var index = 0
        for url in urls {
            guard let document = PDFDocument(url: url) else { continue }
            for pageIndex in 0..<document.pageCount {
                guard let page = document.page(at: pageIndex) else { continue }
                output.insert(page, at: index)
                index += 1
            }
        }
        let url = try freshURL(name)
        guard output.write(to: url) else { throw PDFToolsError.writeFailed }
        Task { @MainActor in RuntimeDiagnostics.shared.log("PDF", "merged \(urls.count) files into \(index) pages") }
        return url
    }

    func extractPages(from url: URL, range: ClosedRange<Int>, name: String = "extract.pdf") throws -> URL {
        guard let document = PDFDocument(url: url) else { throw PDFToolsError.unreadable }
        let output = PDFDocument()
        var index = 0
        for pageIndex in range {
            guard pageIndex >= 0, pageIndex < document.pageCount, let page = document.page(at: pageIndex) else { continue }
            output.insert(page, at: index)
            index += 1
        }
        guard index > 0 else { throw PDFToolsError.emptyRange }
        let target = try freshURL(name)
        guard output.write(to: target) else { throw PDFToolsError.writeFailed }
        Task { @MainActor in RuntimeDiagnostics.shared.log("PDF", "extracted \(index) pages") }
        return target
    }

    // MARK: - Convert

    func images(from url: URL) throws -> [URL] {
        guard let document = PDFDocument(url: url) else { throw PDFToolsError.unreadable }
        var results: [URL] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let image = page.thumbnail(of: size, for: .mediaBox)
            guard let data = image.pngData() else { continue }
            let target = try freshURL("page-\(index + 1).png")
            try data.write(to: target)
            results.append(target)
        }
        Task { @MainActor in RuntimeDiagnostics.shared.log("PDF", "rendered \(results.count) pages to PNG") }
        return results
    }

    func text(from url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else { throw PDFToolsError.unreadable }
        return document.string ?? ""
    }

    // MARK: - Edit

    func rotate(_ url: URL, degrees: Int) throws -> URL {
        guard let document = PDFDocument(url: url) else { throw PDFToolsError.unreadable }
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            page.rotation = (page.rotation + degrees) % 360
        }
        let target = try freshURL("rotated.pdf")
        guard document.write(to: target) else { throw PDFToolsError.writeFailed }
        return target
    }

    func deletePages(_ url: URL, indexes: [Int]) throws -> URL {
        guard let document = PDFDocument(url: url) else { throw PDFToolsError.unreadable }
        for index in indexes.sorted(by: >) where index >= 0 && index < document.pageCount {
            document.removePage(at: index)
        }
        let target = try freshURL("trimmed.pdf")
        guard document.write(to: target) else { throw PDFToolsError.writeFailed }
        return target
    }

    func insertBlankPage(_ url: URL, at index: Int) throws -> URL {
        guard let document = PDFDocument(url: url) else { throw PDFToolsError.unreadable }
        let size = CGSize(width: 595, height: 842)
        let renderer = UIGraphicsImageRenderer(size: size)
        let white = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        guard let blank = PDFPage(image: white) else { throw PDFToolsError.writeFailed }
        document.insert(blank, at: max(0, min(index, document.pageCount)))
        let target = try freshURL("with-blank.pdf")
        guard document.write(to: target) else { throw PDFToolsError.writeFailed }
        return target
    }

    func watermark(_ url: URL, text: String) throws -> URL {
        guard let document = PDFDocument(url: url) else { throw PDFToolsError.unreadable }
        let output = PDFDocument()
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let renderer = UIGraphicsImageRenderer(size: bounds.size)
            let composite = renderer.image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: bounds.size))
                context.cgContext.saveGState()
                context.cgContext.translateBy(x: 0, y: bounds.size.height)
                context.cgContext.scaleBy(x: 1, y: -1)
                page.draw(with: .mediaBox, to: context.cgContext)
                context.cgContext.restoreGState()

                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 48, weight: .bold),
                    .foregroundColor: UIColor.systemRed.withAlphaComponent(0.28)
                ]
                let string = NSAttributedString(string: text, attributes: attributes)
                let size = string.size()
                context.cgContext.translateBy(x: bounds.width / 2, y: bounds.height / 2)
                context.cgContext.rotate(by: -.pi / 6)
                string.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2))
            }
            if let pageImage = PDFPage(image: composite) { output.insert(pageImage, at: index) }
        }
        let target = try freshURL("watermarked.pdf")
        guard output.write(to: target) else { throw PDFToolsError.writeFailed }
        return target
    }

    // MARK: - Security & size

    func protect(_ url: URL, password: String) throws -> URL {
        guard let document = PDFDocument(url: url) else { throw PDFToolsError.unreadable }
        let target = try freshURL("protected.pdf")
        guard document.write(to: target, withOptions: [.userPasswordOption: password, .ownerPasswordOption: password]) else {
            throw PDFToolsError.writeFailed
        }
        return target
    }

    /// Rewrites the document so unused objects and metadata are dropped; this is
    /// the honest "compression" PDFKit offers without rasterising pages.
    func compress(_ url: URL) throws -> URL {
        guard let document = PDFDocument(url: url) else { throw PDFToolsError.unreadable }
        document.documentAttributes = nil
        let target = try freshURL("compressed.pdf")
        guard document.write(to: target) else { throw PDFToolsError.writeFailed }
        RuntimeDiagnostics.shared.log("PDF", "compressed: \(fileSizeKB(url)) KB -> \(fileSizeKB(target)) KB")
        return target
    }

    // MARK: - OCR

    func recognizeText(in url: URL, languages: [String] = ["uk-UA", "en-US"]) async throws -> String {
        guard let document = PDFDocument(url: url) else { throw PDFToolsError.unreadable }
        let started = Date()
        var output = ""
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let image = page.thumbnail(of: CGSize(width: bounds.width * 2, height: bounds.height * 2), for: .mediaBox)
            guard let cgImage = image.cgImage else { continue }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = languages
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            output += lines.joined(separator: "\n") + "\n"
        }
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        Task { @MainActor in RuntimeDiagnostics.shared.log("PDF", "OCR completed in \(ms) ms, \(output.count) chars") }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fileSizeKB(_ url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        return bytes / 1024
    }
}

enum PDFToolsError: Error, Equatable {
    case unreadable, writeFailed, emptyRange
}
