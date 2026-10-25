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
                PDFConvertSection(model: model)
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
                Button("Сканувати документ") { model.showScanner = true }
                Button("Скасувати", role: .cancel) {}
            }
            .photosPicker(isPresented: $model.showPhotoPicker, selection: $model.photoItems, maxSelectionCount: 20, matching: .images)
            .fullScreenCover(isPresented: $model.showCamera) {
                CameraPhotoPicker { image in model.add(image: image) }
            }
            .photosPicker(isPresented: $model.showLogoPicker, selection: $model.logoItem, matching: .images)
            .onChange(of: model.logoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        model.applyLogoWatermark(image)
                    }
                    model.logoItem = nil
                }
            }
            .fullScreenCover(isPresented: $model.showCrop) {
                CropView(image: model.signatureBackground(), onlyFirstPage: $model.cropOnlyFirstPage) { rect in
                    model.applyCrop(rect)
                } onCancel: {
                    model.showCrop = false
                }
            }
            .fullScreenCover(isPresented: $model.showPlacement) {
                AnnotationPlacementView(image: model.signatureBackground(), kind: model.placementKind) { rect in
                    model.placeAnnotation(rect)
                } onCancel: {
                    model.showPlacement = false
                }
            }
            .sheet(isPresented: $model.showViewer) {
                PDFPageViewer(url: model.results.first ?? URL(fileURLWithPath: "/"),
                              pageIndex: model.viewerPage)
            }
            .fullScreenCover(isPresented: $model.showScanner) {
                DocumentScannerView { pages in model.scanPages(pages) }
            }
            .onChange(of: model.photoItems) { _, items in
                if !items.isEmpty { Task { await model.buildFromPhotos() } }
            }
            .fileImporter(isPresented: $model.showPDFImport, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { outcome in
                if case let .success(urls) = outcome { model.mergeFiles(urls.map(FileImport.copy)) }
            }
            .sheet(isPresented: $model.showOffice) { OfficeConvertView() }
            .sheet(isPresented: $model.showFileActions) { PDFFileActionsView() }
            .confirmationDialog("Підпис", isPresented: $model.showSignatureHome, titleVisibility: .visible) {
                if model.savedSignature != nil {
                    Button("Використати збережений підпис") { model.useSavedSignature() }
                }
                Button("Намалювати новий") { model.showSignature = true }
                Button("Скасувати", role: .cancel) {}
            }
            .fullScreenCover(isPresented: $model.showSignature) {
                SignaturePadView(background: model.signatureBackground()) { image, rect in
                    model.signatureImage = image
                    model.saveSignatureImage(image)
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
            .alert("Зняти пароль", isPresented: $model.showRemovePassword) {
                TextField("Поточний пароль", text: $model.passwordText)
                Button("Зняти") { model.removePassword() }
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
            .alert("Видалити сторінки", isPresented: $model.showDeletePage) {
                TextField("2-4", text: $model.deleteRange)
                Button("Видалити", role: .destructive) { model.deleteRangePages() }
                Button("Скасувати", role: .cancel) {}
            }
            .alert("Верхній колонтитул", isPresented: $model.showHeader) {
                TextField("Текст", text: $model.headerText)
                Button("Додати") { model.applyHeader() }
                Button("Скасувати", role: .cancel) {}
            }
            .alert("Перемістити сторінку", isPresented: $model.showMovePage) {
                TextField("З", text: $model.moveFrom)
                TextField("На", text: $model.moveTo)
                Button("Перемістити") { model.movePage() }
                Button("Скасувати", role: .cancel) {}
            }
            .alert("Дублювати сторінку", isPresented: $model.showDuplicatePage) {
                TextField("1", text: $model.duplicateIndex)
                Button("Дублювати") { model.duplicateChosenPage() }
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
