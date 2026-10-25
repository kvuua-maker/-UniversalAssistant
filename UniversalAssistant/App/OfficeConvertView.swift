import SwiftUI
import QuickLook
import UniformTypeIdentifiers

/// Dedicated screen for Word/Excel conversion so the main PDF view stays small.
struct OfficeConvertView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isBusy = false
    @State private var status: String?
    @State private var result: URL?
    @State private var showImporter = false
    @State private var preview: PreviewItem?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Вибрати Word або Excel") { showImporter = true }
                }
                if let result {
                    Section("Результат") {
                        Text(result.lastPathComponent)
                        Button("Перегляд") { preview = PreviewItem(url: result) }
                        ShareLink(item: result) { Text("Поділитися") }
                    }
                }
                if let status {
                    Section("Статус") { Text(status).font(.footnote) }
                }
            }
            .navigationTitle("Office → PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .overlay { if isBusy { ProgressView().padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: ["docx", "doc", "xlsx", "xls", "rtf", "odt"]
                            .compactMap { UTType(filenameExtension: $0) },
                          allowsMultipleSelection: false) { outcome in
                guard case let .success(files) = outcome, let file = files.first else { return }
                Task { await convert(file) }
            }
            .sheet(item: $preview) { item in QuickLookPreview(url: item.url) }
        }
    }

    private func convert(_ url: URL) async {
        isBusy = true
        defer { isBusy = false }
        do {
            result = try await OfficeConversionService.shared.convert(url)
            status = "Готово"
        } catch {
            status = "Не вдалося: \(error)"
        }
    }
}
