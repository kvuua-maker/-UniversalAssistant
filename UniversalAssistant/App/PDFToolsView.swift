import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// PDF workspace: creation, conversion, editing and results. Heavy sections live
/// in PDFToolsSections.swift so this body stays small for the type checker.
struct PDFToolsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = PDFToolsModel()
    @State private var showPhotoChoice = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var showPDFImport = false
    @State private var showOffice = false
    @State private var showFileActions = false
    @State private var showSignature = false
    @State private var showWatermark = false
    @State private var showPassword = false
    @State private var showText = false
    @State private var showBlank = false

    var body: some View {
        NavigationStack {
            List {
                PDFCreateSection(model: model,
                                 onPhotos: { showPhotoChoice = true },
                                 onBlank: { model.runBlank() },
                                 onMerge: { showPDFImport = true },
                                 onOffice: { showOffice = true },
                                 onFileActions: { showFileActions = true },
                                 onSignature: { showSignature = true })
                PDFEditSection(model: model,
                               onRotate: { model.run { Optional(try await PDFToolsEngine.shared.rotate($0)) } },
                               onWatermark: { showWatermark = true },
                               onPassword: { showPassword = true },
                               onCompress: { model.run { Optional(try await PDFToolsEngine.shared.compress($0)) } },
                               onText: { showText = true },
                               onBlankPage: { showBlank = true },
                               onExtract: { model.extractImages() })
                PDFResultsSection(model: model)
            }
            .navigationTitle("PDF-інструменти")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрити") { dismiss() }
                }
            }
            .overlay { if model.isBusy { ProgressView().padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
            .confirmationDialog("PDF з фото", isPresented: $showPhotoChoice, titleVisibility: .visible) {
                Button("Зробити фото") { showCamera = true }
                Button("Вибрати з галереї") { showPhotoPicker = true }
                Button("Скасувати", role: .cancel) {}
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $model.photoItems, maxSelectionCount: 20, matching: .images)
            .onChange(of: model.photoItems) { _, items in
                if !items.isEmpty { Task { await model.buildFromPhotos() } }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPhotoPicker { image in model.add(image: image) }
            }
            .fileImporter(isPresented: $showPDFImport, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { outcome in
                if case let .success(urls) = outcome { model.mergeFiles(urls.map(FileImport.copy)) }
            }
            .sheet(isPresented: $showOffice) { OfficeConvertView() }
            .sheet(isPresented: $showFileActions) { PDFFileActionsView() }
            .sheet(isPresented: $showSignature) {
                SignaturePadView { image in
                    model.signatureImage = image
                    showSignature = false
                    model.statusLine = "Підпис збережено"
                } onCancel: { showSignature = false }
            }
            .sheet(item: $model.previewItem) { item in PDFPreviewSheet(url: item.url) }
            .alert("Водяний знак", isPresented: $showWatermark) {
                TextField("Текст", text: $model.watermarkText)
                Button("Застосувати") { model.applyWatermark() }
                Button("Скасувати", role: .cancel) {}
            }
            .alert("Пароль", isPresented: $showPassword) {
                TextField("Пароль", text: $model.passwordText)
                Button("Захистити") { model.applyPassword() }
                Button("Скасувати", role: .cancel) {}
            }
            .alert("Текст на сторінку", isPresented: $showText) {
                TextField("Текст", text: $model.textToInsert)
                Button("Додати") { model.applyText() }
                Button("Скасувати", role: .cancel) {}
            }
            .alert("Номер сторінки", isPresented: $showBlank) {
                TextField("1", text: $model.blankIndex)
                Button("Вставити") { model.insertBlankPage() }
                Button("Скасувати", role: .cancel) {}
            }
        }
    }
}
