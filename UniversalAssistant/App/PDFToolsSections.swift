import SwiftUI

struct PDFCreateSection: View {
    let model: PDFToolsModel

    var body: some View {
        Section("Створити") {
            Button("PDF з фото") { model.showPhotoChoice = true }
            Button("Порожній PDF") { model.runBlank() }
            Button("Об’єднати PDF-файли") { model.showPDFImport = true }
            Button("Word / Excel → PDF") { model.showOffice = true }
            Button("Інструменти для файлу") { model.showFileActions = true }
            Button(model.signatureImage == nil ? "Намалювати підпис" : "Перемалювати підпис") { model.showSignature = true }
        }
    }
}

struct PDFConvertSection: View {
    @Bindable var model: PDFToolsModel

    var body: some View {
        Section("Конвертувати та оформити") {
            if model.results.isEmpty {
                Text("Спочатку створіть або виберіть PDF")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Button("PDF → Текст") { model.exportText() }
                Button("PDF → PNG") { model.exportPNG() }
                Button("OCR: розпізнати текст") { model.runOCR() }
                Button("Обрізати поля (10 pt)") { model.cropPages() }
                Button("Розмір A4") { model.resizeA4() }
                Button("Розмір Letter") { model.resizeLetter() }
                Button("Колонтитули (номер + дата)") { model.addFooters() }
                HStack {
                    TextField("Пошук по тексту", text: $model.searchQuery)
                    Button("Знайти") { model.findInDocument() }
                        .buttonStyle(.borderless)
                }
                if let result = model.searchResult {
                    Text(result).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct PDFEditSection: View {
    let model: PDFToolsModel

    var body: some View {
        Section("Редагувати") {
            if model.results.isEmpty {
                Text("Спочатку створіть або виберіть PDF")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if let current = model.results.first {
                Button("Повернути на 90°") { model.rotate(current) }
                Button("Додати текст") { model.showText = true }
                Button("Водяний знак") { model.showWatermark = true }
                Button("Захистити паролем") { model.showPassword = true }
                Button("Зняти пароль") { model.passwordText = ""; model.showRemovePassword = true }
                Button("Стиснути") { model.compress(current) }
                Button("Вставити порожню сторінку") { model.showBlank = true }
                Button("Витягнути зображення") { model.extractImages() }
                Button("Розділити: витягти сторінки") { model.showSplit = true }
                Button("Видалити сторінку") { model.showDeletePage = true }
                Button("Дублювати першу сторінку") { model.duplicateFirstPage() }
                Menu("Анотація") {
                    Button("Маркер") { model.addAnnotation(.highlight) }
                    Button("Підкреслення") { model.addAnnotation(.underline) }
                    Button("Закреслення") { model.addAnnotation(.strikeOut) }
                    Button("Прямокутник") { model.addAnnotation(.square) }
                    Button("Коло") { model.addAnnotation(.circle) }
                    Button("Коментар") { model.addAnnotation(.comment) }
                }
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
            if model.results.count > 1 {
                Button("Скасувати останню дію") { model.undo() }
            }
            if model.canRedo {
                Button("Повторити дію") { model.redo() }
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
            SaveToFilesButton(url: url)
                .buttonStyle(.borderless)
            Menu {
                Button("Перегляд") { model.previewItem = PreviewTarget(url: url) }
                Button("Друк") { model.printPDF(url) }
                Button("Видалити зі списку") { model.results.removeAll { $0 == url } }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.borderless)
        }
    }
}
