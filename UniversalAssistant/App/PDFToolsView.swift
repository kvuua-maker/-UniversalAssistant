import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

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
                if !results.isEmpty {
                    Section("Результати") {
                        ForEach(results, id: \.self) { url in
                            HStack {
                                Text(url.lastPathComponent).lineLimit(1)
                                Spacer()
                                Button("Поділитися") { shareURL = url; showShareSheet = true }
                            }
                        }
                    }
                }
                if let statusLine {
                    Section("Статус") { Text(statusLine).font(.footnote) }
                }
            }
            .navigationTitle("PDF-інструменти")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .overlay { if isBusy { ProgressView().controlSize(.large).padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
            .fileImporter(isPresented: $showPDFImporter, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
                if case let .success(urls) = result { importedPDFs = urls }
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
