import Foundation
import UIKit

extension PDFToolsModel {
    func signatureBackground() -> UIImage? {
        guard let url = results.first else { return nil }
        return PDFToolsEngine.shared.pageImageSync(url)
    }

    func applySignature(image: UIImage, rect: CGRect) {
        guard let url = results.first else { showSignature = false; return }
        showSignature = false
        run { Optional(try await PDFToolsEngine.shared.insertSignature(url, signature: image, normalizedRect: rect)) }
    }

    func rotate(_ url: URL) {
        run { Optional(try await PDFToolsEngine.shared.rotate(url, degrees: 90)) }
    }

    func compress(_ url: URL) {
        run { Optional(try await PDFToolsEngine.shared.compress(url)) }
    }

    var blankIndex: String {
        get { _blankIndex }
        set { _blankIndex = newValue }
    }

    func runBlank() {
        run { Optional(try await PDFToolsEngine.shared.makeBlankPDF()) }
    }

    func mergeFiles(_ urls: [URL]) {
        guard urls.count >= 1 else { return }
        importedPDFs = urls
        run { Optional(try await PDFToolsEngine.shared.merge(urls)) }
    }

    func add(image: UIImage) {
        run { Optional(try await PDFToolsEngine.shared.makePDF(from: [image])) }
    }

    func applyWatermark() {
        guard let url = results.first, !watermarkText.isEmpty else { return }
        run { Optional(try await PDFToolsEngine.shared.watermark(url, text: self.watermarkText)) }
    }

    func applyPassword() {
        guard let url = results.first, !passwordText.isEmpty else { return }
        run { Optional(try await PDFToolsEngine.shared.protect(url, password: self.passwordText)) }
    }

    func applyText() {
        guard let url = results.first, !textToInsert.isEmpty else { return }
        run { Optional(try await PDFToolsEngine.shared.addText(url, text: self.textToInsert)) }
    }

    func insertBlankPage() {
        guard let url = results.first, let index = Int(blankIndex) else { return }
        run { Optional(try await PDFToolsEngine.shared.insertBlankPage(url, at: max(0, index - 1))) }
    }

    func extractImages() {
        guard let url = results.first else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let images = try await PDFToolsEngine.shared.imagesOrRendered(from: url)
                results.insert(contentsOf: images, at: 0)
                statusLine = "Витягнуто зображень: \(images.count)"
            } catch {
                let message = (error as? PDFToolsError)?.userMessage
                    ?? "Не вдалося витягнути зображення. Можливо, файл захищений паролем або пошкоджений."
                alertMessage = message
            }
        }
    }
}
