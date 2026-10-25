import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// PDF workspace shell. All state lives in PDFToolsModel and the sections are
/// separate views, keeping every expression small enough to type-check.
struct PDFToolsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = PDFToolsModel()

    var body: some View {
        NavigationStack {
            List {
                PDFCreateSection(model: model)
                PDFEditSection(model: model)
                PDFResultsSection(model: model)
            }
            .navigationTitle("PDF-інструменти")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрити") { dismiss() }
                }
            }
            .modifier(PDFToolsBindings(model: model))
        }
    }
}

/// Pickers, sheets and alerts attached to the workspace.
private struct PDFToolsBindings: ViewModifier {
    @Bindable var model: PDFToolsModel

    func body(content: Content) -> some View {
        content
            .overlay { if model.isBusy { ProgressView().padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
            .confirmationDialog("PDF з фото", isPresented: $model.showPhotoChoice, titleVisibility: .visible) {
                Button("Зробити фото") { model.showCamera = true }
                Button("Вибрати з галереї") { model.showPhotoPicker = true }
                Button("Скасувати", role: .cancel) {}
            }
            .photosPicker(isPresented: $model.showPhotoPicker, selection: $model.photoItems, maxSelectionCount: 20, matching: .images)
            .fullScreenCover(isPresented: $model.showCamera) {
                CameraPhotoPicker { image in model.add(image: image) }
            }
            .onChange(of: model.photoItems) { _, items in
                if !items.isEmpty { Task { await model.buildFromPhotos() } }
            }
            .fileImporter(isPresented: $model.showPDFImport, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { outcome in
                if case let .success(urls) = outcome { model.mergeFiles(urls.map(FileImport.copy)) }
            }
            .sheet(isPresented: $model.showOffice) { OfficeConvertView() }
            .sheet(isPresented: $model.showFileActions) { PDFFileActionsView() }
            .fullScreenCover(isPresented: $model.showSignature) {
                SignaturePadView(background: model.signatureBackground()) { image, rect in
                    model.signatureImage = image
                    model.applySignature(image: image, rect: rect)
                } onCancel: {
                    model.showSignature = false
                }
            }
            .sheet(item: $model.previewItem) { item in PDFPreviewSheet(url: item.url) }
            .modifier(PDFToolsAlerts(model: model))
    }
}

private struct PDFToolsAlerts: ViewModifier {
    @Bindable var model: PDFToolsModel

    func body(content: Content) -> some View {
        content
            .alert("Водяний знак", isPresented: $model.showWatermark) {
                TextField("Текст", text: $model.watermarkText)
                Button("Застосувати") { model.applyWatermark() }
                Button("Скасувати", role: .cancel) {}
            }
            .alert("Пароль", isPresented: $model.showPassword) {
                TextField("Пароль", text: $model.passwordText)
                Button("Захистити") { model.applyPassword() }
                Button("Скасувати", role: .cancel) {}
            }
            .alert("Текст на сторінку", isPresented: $model.showText) {
                TextField("Текст", text: $model.textToInsert)
                Button("Додати") { model.applyText() }
                Button("Скасувати", role: .cancel) {}
            }
            .alert("Витягти сторінки", isPresented: $model.showSplit) {
                TextField("1-2", text: $model.splitRange)
                Button("Витягти") { model.splitPages() }
                Button("Скасувати", role: .cancel) {}
            }
            .alert("Видалити сторінку", isPresented: $model.showDeletePage) {
                TextField("1", text: $model.deletePageIndex)
                Button("Видалити", role: .destructive) { model.deleteChosenPage() }
                Button("Скасувати", role: .cancel) {}
            }
            .alert("Номер сторінки", isPresented: $model.showBlank) {
                TextField("1", text: $model.blankIndex)
                Button("Вставити") { model.insertBlankPage() }
                Button("Скасувати", role: .cancel) {}
            }
            .alert("Помилка", isPresented: Binding(
                get: { model.alertMessage != nil },
                set: { if !$0 { model.alertMessage = nil } }
            )) {
                Button("OK", role: .cancel) { model.alertMessage = nil }
            } message: {
                Text(model.alertMessage ?? "")
            }
    }
}
