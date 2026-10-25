import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import QuickLook

/// Standalone PDF workspace. Every operation runs off the main actor through
/// PDFToolsEngine; results can be previewed, shared, printed or saved to Files.
struct PDFToolsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var isBusy = false
    @State private var statusLine: String?
    @State private var results: [URL] = []
    @State private var importedPDFs: [URL] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPDFImporter = false
    @State private var showPhotoPicker = false
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    @State private var watermarkText = ""
    @State private var passwordText = ""
    @State private var showWatermarkPrompt = false
    @State private var showPasswordPrompt = false
    @State private var textToInsert = ""
    @State private var showTextPrompt = false
    @State private var previewItem: PreviewItem?
    @State private var annotationKind: PDFAnnotationKind = .highlight
    @State private var signatureImage: UIImage?
    @State private var showSignaturePad = false
    @State private var officeURL: URL?
    @State private var showOfficeImporter = false
    @State private var previewOffice: PreviewItem?

    var body: some View {
        NavigationStack {
            List {
                Section("Створити") {
                    Button("PDF з фото") { showPhotoPicker = true }
                    Button("Порожній PDF (1 сторінка)") { run { Optional(try await PDFToolsEngine.shared.makeBlankPDF()) } }
                }
                Section("Об’єднати та розділити") {
                    Button("Вибрати PDF для об’єднання") { showPDFImporter = true }
                    if importedPDFs.count >= 2 {
                        Button("Об’єднати \(importedPDFs.count) файли") {
                            run { Optional(try await PDFToolsEngine.shared.merge(importedPDFs)) }
                        }
                    }
                    if let first = results.first {
                        Button("Витягнути першу сторінку") {
                            run { Optional(try await PDFToolsEngine.shared.extractPages(from: first, range: 0...0)) }
                        }
                    }
                }
                Section("Конвертувати") {
                    ForEach(results, id: \.self) { url in
                        Button("Текст з \(url.lastPathComponent)") {
                            run { let text = try await PDFToolsEngine.shared.text(from: url); statusLine = String(text.prefix(400)); return nil }
                        }
                        Button("PNG з \(url.lastPathComponent)") {
                            run { let images = try await PDFToolsEngine.shared.images(from: url); statusLine = "Створено \(images.count) PNG"; return nil }
                        }
                        Button("OCR \(url.lastPathComponent)") {
                            run { let text = try await PDFToolsEngine.shared.recognizeText(in: url); statusLine = String(text.prefix(400)); return nil }
                        }
                    }
                }
                Section("Редагувати") {
                    ForEach(results, id: \.self) { url in
                        Button("Повернути 90°") { run { Optional(try await PDFToolsEngine.shared.rotate(url, degrees: 90)) } }
                        Button("Водяний знак") { watermarkText = ""; showWatermarkPrompt = true }
                        Button("Захистити паролем") { passwordText = ""; showPasswordPrompt = true }
                        Button("Стиснути") { run { Optional(try await PDFToolsEngine.shared.compress(url)) } }
                    }
                }
                Section("Office → PDF") {
                    Button("Вибрати Word / Excel") { showOfficeImporter = true }
                    if let officeURL {
                        Button("Відкрити \(officeURL.lastPathComponent)") { previewOffice = PreviewItem(url: officeURL) }
                        Button("Друк / Зберегти як PDF") { printPDF(officeURL) }
                    }
                }
                Section("Підпис") {
                    Button(signatureImage == nil ? "Намалювати підпис" : "Перемалювати підпис") { showSignaturePad = true }
                    ForEach(results, id: \.self) { url in
                        Button("Вставити підпис у \(url.lastPathComponent)") {
                            guard let signatureImage else { statusLine = "Спочатку намалюйте підпис"; return }
                            run { Optional(try await PDFToolsEngine.shared.insertSignature(url, signature: signatureImage)) }
                        }
                    }
                }
                Section("Сторінки") {
                    ForEach(results, id: \.self) { url in
                        Button("Дублювати першу сторінку") { run { Optional(try await PDFToolsEngine.shared.duplicatePage(url, index: 0)) } }
                        Button("Перемістити першу в кінець") { run { Optional(try await PDFToolsEngine.shared.movePage(url, from: 0, to: 1)) } }
                        Button("Обрізати поля (10 pt)") { run { Optional(try await PDFToolsEngine.shared.crop(url, inset: 10)) } }
                        Button("Розмір A4") { run { Optional(try await PDFToolsEngine.shared.resize(url, to: CGSize(width: 595, height: 842))) } }
                        Button("Розмір Letter") { run { Optional(try await PDFToolsEngine.shared.resize(url, to: CGSize(width: 612, height: 792))) } }
                        Button("Колонтитули (номер + дата)") { run { Optional(try await PDFToolsEngine.shared.addFooter(url)) } }
                    }
                }
                Section("Текст і анотації") {
                    ForEach(results, id: \.self) { url in
                        Button("Додати текст") { textToInsert = ""; showTextPrompt = true }
                        Picker("Тип", selection: $annotationKind) {
                            ForEach(PDFAnnotationKind.allCases, id: \.self) { kind in
                                Text(kind.rawValue).tag(kind)
                            }
                        }
                        Button("Додати \(annotationKind.rawValue)") {
                            run { Optional(try await PDFToolsEngine.shared.addAnnotation(url, kind: annotationKind)) }
                        }
                    }
                }
                if !results.isEmpty {
                    Section("Результати") {
                        ForEach(results, id: \.self) { url in
                            HStack {
                                Text(url.lastPathComponent).lineLimit(1)
                                Spacer()
                                Button("Перегляд") { previewItem = PreviewItem(url: url) }
                                Button("Поділитися") { shareURL = url; showShareSheet = true }
                                Button("Друк") { printPDF(url) }
                            }
                        }
                    }
                }
                if let statusLine {
                    Section("Статус") {
                        Text(statusLine).font(.footnote)
                        if results.count > 1 {
                            Button("Скасувати останню дію") { results.removeFirst() }
                        }
                    }
                }
            }
            .navigationTitle("PDF-інструменти")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .overlay { if isBusy { ProgressView().controlSize(.large).padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
            .fileImporter(isPresented: $showPDFImporter, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
                if case let .success(urls) = result { importedPDFs = urls }
            }
            .fileImporter(isPresented: $showOfficeImporter,
                          allowedContentTypes: ["docx", "doc", "xlsx", "xls"].compactMap { UTType(filenameExtension: $0) }) { result in
                if case let .success(urls) = result, let first = urls.first { officeURL = first }
            }
            .sheet(isPresented: $showSignaturePad) {
                SignaturePadView { image in
                    signatureImage = image
                    showSignaturePad = false
                    statusLine = "Підпис збережено"
                } onCancel: {
                    showSignaturePad = false
                }
            }
            .sheet(item: $previewOffice) { item in
                QuickLookPreview(url: item.url)
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItems, maxSelectionCount: 20, matching: .images)
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await buildFromPhotos(items) }
            }
            .sheet(isPresented: $showShareSheet) {
                if let shareURL { ShareSheet(items: [shareURL]) }
            }
            .alert("Текст водяного знака", isPresented: $showWatermarkPrompt) {
                TextField("Наприклад: ЧЕРНЕТКА", text: $watermarkText)
                Button("Застосувати") {
                    guard let url = results.first else { return }
                    run { Optional(try await PDFToolsEngine.shared.watermark(url, text: watermarkText)) }
                }
                Button("Скасувати", role: .cancel) {}
            }
            .sheet(item: $previewItem) { item in
                QuickLookPreview(url: item.url)
            }
            .alert("Текст для додавання", isPresented: $showTextPrompt) {
                TextField("Текст", text: $textToInsert)
                Button("Додати") {
                    guard let url = results.first, !textToInsert.isEmpty else { return }
                    run { Optional(try await PDFToolsEngine.shared.addText(url, text: textToInsert)) }
                }
                Button("Скасувати", role: .cancel) {}
            }
            .alert("Пароль", isPresented: $showPasswordPrompt) {
                TextField("Пароль", text: $passwordText)
                Button("Захистити") {
                    guard let url = results.first, !passwordText.isEmpty else { return }
                    run { Optional(try await PDFToolsEngine.shared.protect(url, password: passwordText)) }
                }
                Button("Скасувати", role: .cancel) {}
            }
        }
    }

    private func buildFromPhotos(_ items: [PhotosPickerItem]) async {
        isBusy = true
        defer { isBusy = false }
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                images.append(image)
            }
        }
        guard !images.isEmpty else { statusLine = "Не вдалося прочитати фото"; return }
        do {
            let url = try await PDFToolsEngine.shared.makePDF(from: images)
            results.insert(url, at: 0)
            statusLine = "PDF створено: \(images.count) сторінок"
        } catch {
            statusLine = "Помилка: \(error)"
        }
        photoItems = []
    }

    private func printPDF(_ url: URL) {
        guard UIPrintInteractionController.isPrintingAvailable else {
            statusLine = "Друк недоступний на цьому пристрої"
            return
        }
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo.printInfo()
        info.jobName = url.lastPathComponent
        info.outputType = .general
        controller.printInfo = info
        controller.printingItem = url
        controller.present(animated: true)
    }

    private func run(_ operation: @escaping () async throws -> URL?) {
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                if let url = try await operation() { results.insert(url, at: 0) }
            } catch {
                statusLine = "Помилка: \(error)"
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}


struct PreviewItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}


/// Minimal finger-drawing surface for a signature.
struct SignaturePadView: View {
    let onSave: (UIImage) -> Void
    let onCancel: () -> Void
    @State private var controller = SignaturePadController()

    var body: some View {
        NavigationStack {
            VStack {
                SignatureCanvas(controller: controller)
                    .background(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.3)))
                    .padding()
                Text("Намалюйте підпис пальцем").font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("Підпис")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { onCancel() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        if let image = controller.render() { onSave(image) }
                    }
                }
            }
        }
    }
}

final class SignaturePadController {
    var strokes: [[CGPoint]] = []
    var current: [CGPoint] = []

    func render(size: CGSize = CGSize(width: 600, height: 240)) -> UIImage? {
        guard !strokes.isEmpty else { return nil }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setStroke()
            context.cgContext.setLineWidth(3)
            context.cgContext.setLineCap(.round)
            for stroke in strokes where stroke.count > 1 {
                context.cgContext.move(to: stroke[0])
                for point in stroke.dropFirst() { context.cgContext.addLine(to: point) }
                context.cgContext.strokePath()
            }
        }
    }
}

struct SignatureCanvas: UIViewRepresentable {
    let controller: SignaturePadController

    func makeUIView(context: Context) -> CanvasView {
        let view = CanvasView()
        view.controller = controller
        view.backgroundColor = .white
        return view
    }
    func updateUIView(_ view: CanvasView, context: Context) {}

    final class CanvasView: UIView {
        var controller: SignaturePadController?
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let point = touches.first?.location(in: self) else { return }
            controller?.current = [point]
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let point = touches.first?.location(in: self) else { return }
            controller?.current.append(point)
            setNeedsDisplay()
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let controller, !controller.current.isEmpty else { return }
            controller.strokes.append(controller.current)
            controller.current = []
            setNeedsDisplay()
        }
        override func draw(_ rect: CGRect) {
            guard let controller, let context = UIGraphicsGetCurrentContext() else { return }
            UIColor.black.setStroke()
            context.setLineWidth(3)
            context.setLineCap(.round)
            for stroke in controller.strokes + [controller.current] where stroke.count > 1 {
                context.move(to: stroke[0])
                for point in stroke.dropFirst() { context.addLine(to: point) }
                context.strokePath()
            }
        }
    }
}
