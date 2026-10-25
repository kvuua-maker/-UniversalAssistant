import SwiftUI

struct PDFCreateSection: View {
    let model: PDFToolsModel
    let onPhotos: () -> Void
    let onBlank: () -> Void
    let onMerge: () -> Void
    let onOffice: () -> Void
    let onFileActions: () -> Void
    let onSignature: () -> Void

    var body: some View {
        Section("Створити") {
            Button("PDF з фото", action: onPhotos)
            Button("Порожній PDF", action: onBlank)
            Button("Об’єднати PDF-файли", action: onMerge)
            Button("Word / Excel → PDF", action: onOffice)
            Button("Інструменти для файлу", action: onFileActions)
            Button(model.signatureImage == nil ? "Намалювати підпис" : "Перемалювати підпис", action: onSignature)
        }
    }
}

struct PDFEditSection: View {
    let model: PDFToolsModel
    let onRotate: (URL) -> Void
    let onWatermark: () -> Void
    let onPassword: () -> Void
    let onCompress: (URL) -> Void
    let onText: () -> Void
    let onBlankPage: () -> Void
    let onExtract: () -> Void

    var body: some View {
        Section("Редагувати") {
            if model.results.isEmpty {
                Text("Спочатку створіть або виберіть PDF")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if let current = model.results.first {
                Button("Повернути на 90°") { onRotate(current) }
                Button("Додати текст") { onText() }
                Button("Водяний знак") { onWatermark() }
                Button("Захистити паролем") { onPassword() }
                Button("Стиснути") { onCompress(current) }
                Button("Вставити порожню сторінку") { onBlankPage() }
                Button("Витягнути зображення") { onExtract() }
            }
        }
    }
}

struct PDFResultsSection: View {
    @Bindable var model: PDFToolsModel

    var body: some View {
        Section("Результати") {
            if model.results.isEmpty {
                Text("Тут з’являться створені файли").font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(model.results, id: \.self) { url in
                    PDFResultRow(model: model, url: url)
                }
            }
            if let status = model.statusLine {
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

private struct PDFResultRow: View {
    @Bindable var model: PDFToolsModel
    let url: URL

    var body: some View {
        HStack {
            Text(url.lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Menu {
                Button("Перегляд") { model.previewItem = PreviewItem(url: url) }
                Button("Друк") { model.printPDF(url) }
                Button("Видалити зі списку") { model.results.removeAll { $0 == url } }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.borderless)
        }
    }
}
