import SwiftUI
import UniformTypeIdentifiers

/// File-level PDF actions in their own screen so the main workspace stays
/// small enough for the type checker.
struct PDFFileActionsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var file: URL?
    @State private var results: [URL] = []
    @State private var status: String?
    @State private var isBusy = false
    @State private var showPicker = false
    @State private var blankPrompt = false
    @State private var blankIndex = "1"
    @State private var moverItem: PreviewItem?
    @State private var previewItem: PreviewItem?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Вибрати PDF") { showPicker = true }
                }
                if file != nil {
                    Section("Дії") {
                        Button("Витягнути зображення") { extract() }
                        Button("Вставити порожню сторінку") { blankIndex = "1"; blankPrompt = true }
                        Button("Перемістити анотації пальцем") { if let file { moverItem = PreviewItem(url: file) } }
                    }
                }
                if !results.isEmpty {
                    Section("Результати") {
                        ForEach(results, id: \.self) { url in
                            VStack(alignment: .leading) {
                                Text(url.lastPathComponent).lineLimit(1)
                                HStack {
                                    Button("Перегляд") { previewItem = PreviewItem(url: url) }
                                    SaveToFilesButton(url: url)
                                }
                            }
                        }
                    }
                }
                if let status {
                    Section("Статус") { Text(status).font(.footnote) }
                }
            }
            .navigationTitle("Інструменти для файлу")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .overlay { if isBusy { ProgressView().padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
            .fileImporter(isPresented: $showPicker, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { outcome in
                guard case let .success(files) = outcome, let first = files.first else { return }
                file = first
            }
            .alert("Номер сторінки для вставки", isPresented: $blankPrompt) {
                TextField("1", text: $blankIndex)
                Button("Вставити") { insertBlank() }
                Button("Скасувати", role: .cancel) {}
            }
            .sheet(item: $moverItem) { item in AnnotationMoverView(url: item.url) }
            .sheet(item: $previewItem) { item in QuickLookPreview(url: item.url) }
        }
    }

    private func extract() {
        guard let file else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let images = try await PDFToolsEngine.shared.imagesOrRendered(from: file)
                results.insert(contentsOf: images, at: 0)
                status = "Витягнуто: \(images.count)"
            } catch {
                status = "Не вдалося: \(error). Файл доступний для повторної спроби."
            }
        }
    }

    private func insertBlank() {
        guard let file, let index = Int(blankIndex) else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let updated = try await PDFToolsEngine.shared.insertBlankPage(file, at: max(0, index - 1))
                self.file = updated
                results.insert(updated, at: 0)
                status = "Сторінку вставлено"
            } catch {
                status = "Не вдалося: \(error)"
            }
        }
    }
}
