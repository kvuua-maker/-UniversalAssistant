import ContactsUI
import MessageUI
import SwiftUI

struct AssistantHomeView: View {
    @Bindable var model: AssistantViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingDiagnostics = false

    var body: some View {
        TabView {
            NavigationStack {
                ZStack {
                    PremiumAssistantBackdrop(colorScheme: colorScheme)
                        .ignoresSafeArea()
                    ScrollView {
                        VStack(spacing: 22) {
                            VStack(spacing: 5) {
                                Text("UniversalAssistant")
                                    .font(.system(.title2, design: .rounded, weight: .semibold))
                                Text(model.statusText)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier("assistant.status")
                            }
                            .padding(.top, 18)

                            if showsOrb {
                                Button(action: model.toggleListening) {
                                    AssistantVoiceOrb(
                                        isListening: model.isListening,
                                        isProcessing: model.resultState == .processing,
                                        reduceMotion: reduceMotion
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(!model.voiceInputEnabled)
                                .accessibilityLabel(model.isListening ? Text("stop_listening") : Text("start_listening"))
                                .accessibilityIdentifier("assistant.voice-orb")
                            }

                            if !model.visibleVoiceTranscript.isEmpty {
                                Text(model.visibleVoiceTranscript)
                                    .font(.body)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.primary.opacity(0.86))
                                    .frame(maxWidth: 520)
                                    .padding(.horizontal, 14)
                                    .accessibilityIdentifier("assistant.voice-transcript")
                            }

                            if model.shouldOfferSettings,
                               let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                                Link("settings", destination: settingsURL)
                                    .buttonStyle(.bordered)
                                    .accessibilityIdentifier("assistant.permission-settings")
                            }

                            CompactResultCard(state: model.resultState, onReportIssue: {
                                Task { await model.reportWrongResult() }
                            }, onScannerAction: model.performScannerAction, onOCRAction: model.performOCRAction, onTranslationAction: model.performTranslationAction, onResultAction: model.performResultAction, onActionRequiredChoice: model.resolveActionRequiredChoice, onToggleFavoritePlace: { place in
                                model.toggleFavorite(place: place)
                            }, onToggleFavoriteOffer: { offer in
                                model.toggleFavorite(offer: offer)
                            }, isFavorite: { identifier in
                                model.isFavorite(id: identifier)
                            })
                                .frame(maxWidth: 560)
                                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98)), removal: .opacity))

                            RecordingStatusPill(state: model.recorder.state)
                            Spacer(minLength: 28)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 18)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    AdaptiveRequestComposer(text: Binding(
                        get: { model.input },
                        set: { model.updateComposerTextFromUser($0) }
                    ), submit: model.submit)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 6)
                        .background(.ultraThinMaterial)
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    NavigationLink(destination: QuickLaunchView(capabilities: .init(
                        actionButton: .unavailable, backTap: .available, appShortcut: .available,
                        homeScreenShortcut: .available, assistiveTouch: .available))) {
                        Image(systemName: "bolt.circle")
                    }.accessibilityLabel("Швидкий запуск")
                    Button {
                        showingDiagnostics = true
                    } label: {
                        Image(systemName: "stethoscope")
                    }.accessibilityLabel("Діагностика")
                    NavigationLink(destination: AssistantSettingsView(model: model)) {
                        Image(systemName: "gearshape")
                    }.accessibilityLabel("Settings")
                }
            }
            .tabItem { Label("home", systemImage: "house") }
            MyTasksView(items: model.personalTasks)
                .tabItem { Label("my_tasks", systemImage: "checklist") }
            FavoritesView(favorites: model.favorites)
                .tabItem { Label("favorites", systemImage: "star") }
        }
        .preferredColorScheme(model.presentationPreferences.appearance == .dark ? .dark : model.presentationPreferences.appearance == .light ? .light : nil)
        .tint(model.presentationPreferences.accent.color)
        .sheet(isPresented: $showingDiagnostics) { DiagnosticsView() }
        // AppText resolves strings at render time; rebuilding the tree on
        // language change is what makes the picker take effect immediately.
        .id(model.languageConfiguration.uiLanguage)
        .sheet(item: Binding(
            get: { model.capabilityPresentation },
            set: { if $0 == nil { model.dismissCapabilityPresentation() } }
        )) { presentation in
            switch presentation {
            case .camera:
                SystemCameraCapture { _ in model.dismissCapabilityPresentation() }
            case .ocrCamera:
                SystemCameraCapture(onCapturedImage: model.handleCapturedOCRImage)
            case .ocrDocuments:
                AuthorizedDocumentPicker(onSelection: model.handleSelectedOCRDocuments)
            case let .scanDocument(mode):
                SystemDocumentScannerView(onPages: { model.handleScannedDocument($0, mode: mode) }, onFailure: model.handleDocumentScannerFailure)
            case .scanner:
                LiveCodeScannerView(onResult: model.handleScannedCode, onUnavailable: model.handleScannerUnavailable)
            case .documents:
                AuthorizedDocumentPicker { _ in model.dismissCapabilityPresentation() }
            case let .pdfSourcePicker(_, text):
                PDFCreationSourcePickerView(
                    onText: { model.selectPDFCreationSource(.text, suggestedText: text) },
                    onPhoto: { model.selectPDFCreationSource(.photo, suggestedText: nil) },
                    onFile: { model.selectPDFCreationSource(.document, suggestedText: nil) }
                )
            case let .pdfTextInput(text):
                PDFTextCreationView(initialText: text ?? "", onCreate: model.createPDFFromText)
            case .pdfPhotoPicker:
                SystemPhotoLibraryPicker(onSelection: model.handleSelectedPDFPhoto)
            case let .pdfWorkflow(operation, text):
                AuthorizedDocumentPicker { model.handleSelectedPDFDocuments($0, operation: operation, text: text) }
            case let .share(value):
                SystemShareSheet(items: [value])
            case let .contactImport(data):
                VCardImportConfirmationView(data: data, onComplete: model.dismissCapabilityPresentation)
            case let .contactAccess(query, command):
                ContactAccessButton(
                    queryString: query,
                    ignoredEmails: nil,
                    ignoredPhoneNumbers: nil,
                    approvalCallback: { identifiers in model.handleContactAccessGranted(identifiers, for: command) }
                )
                .contactAccessButtonCaption(.phone)
                .padding()
            case let .contactCard(identifier):
                ExistingContactCardView(identifier: identifier, onComplete: model.dismissCapabilityPresentation)
            case let .translationTarget(text):
                TranslationTargetPickerView(text: text, onSelect: model.startTranslation)
            case .photoLibrary:
                SystemPhotoLibraryPicker(onSelection: model.handleSelectedPhotoLibraryAsset)
            case .audioRoutes:
                AudioRouteSelectionView()
            case let .photoAsset(identifier):
                PhotoAssetPresentationView(localIdentifier: identifier, onOCR: model.handlePhotoOCRImage)
            case let .photoOCR(identifier):
                PhotoAssetPresentationView(localIdentifier: identifier, onOCR: model.handlePhotoOCRImage, automaticAction: .ocr)
            case let .photoShare(identifier):
                PhotoAssetPresentationView(localIdentifier: identifier, onOCR: model.handlePhotoOCRImage, automaticAction: .share)
            case let .audioFile(url):
                SystemShareSheet(items: [url])
            case let .documentFile(url):
                SystemShareSheet(items: [url])
            case let .documentFiles(urls):
                SystemShareSheet(items: urls)
            case let .translation(plan):
                AppleTranslationExecutionView(plan: plan, onResult: model.handleTranslationResult, onFailure: model.handleTranslationFailure)
            case let .message(recipients, body):
                if MFMessageComposeViewController.canSendText() {
                    SystemMessageComposer(recipients: recipients, body: body) { _ in model.dismissCapabilityPresentation() }
                } else {
                    Text("request_unavailable")
                }
            case let .email(recipients, subject, body):
                if MFMailComposeViewController.canSendMail() {
                    SystemMailComposer(recipients: recipients, subject: subject, body: body) { _ in model.dismissCapabilityPresentation() }
                } else {
                    Text("request_unavailable")
                }
            }
        }
    }

    private var showsOrb: Bool {
        model.isVoiceOrbAvailable
    }
}

private struct PremiumAssistantBackdrop: View {
    let colorScheme: ColorScheme

    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color(red: 0.018, green: 0.025, blue: 0.065) : Color(red: 0.965, green: 0.968, blue: 0.985))
            RadialGradient(
                colors: [Color.indigo.opacity(colorScheme == .dark ? 0.22 : 0.10), .clear],
                center: .top,
                startRadius: 20,
                endRadius: 520
            )
        }
    }
}

private struct AssistantVoiceOrb: View {
    let isListening: Bool
    let isProcessing: Bool
    let reduceMotion: Bool
    @State private var breathes = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.indigo.opacity(0.22))
                .frame(width: 190, height: 190)
                .blur(radius: 24)
                .scaleEffect(breathes ? 1.08 : 0.94)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.48, green: 0.22, blue: 1.0), Color(red: 0.12, green: 0.55, blue: 1.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Circle().stroke(.white.opacity(0.22), lineWidth: 1)
                }
                .shadow(color: .indigo.opacity(0.52), radius: 30, y: 12)
                .frame(width: 142, height: 142)
            Image(systemName: isListening ? "waveform" : (isProcessing ? "sparkles" : "mic.fill"))
                .font(.system(size: 42, weight: .medium, design: .rounded))
                .symbolEffect(.variableColor.iterative, options: reduceMotion ? .nonRepeating : .repeating, isActive: isListening || isProcessing)
                .foregroundStyle(.white)
        }
        .frame(width: 210, height: 210)
        .contentShape(Circle())
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { breathes = true }
        }
        .accessibilityAddTraits(.isButton)
    }
}

private struct PDFCreationSourcePickerView: View {
    let onText: () -> Void
    let onPhoto: () -> Void
    let onFile: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Button(action: onText) { Label("Текст", systemImage: "text.alignleft") }
                Button(action: onPhoto) { Label("Фото", systemImage: "photo") }
                Button(action: onFile) { Label("Файл", systemImage: "doc") }
            }
            .navigationTitle("Створити PDF")
        }
    }
}

private struct PDFTextCreationView: View {
    @State private var text: String
    let onCreate: (String) -> Void

    init(initialText: String, onCreate: @escaping (String) -> Void) {
        _text = State(initialValue: initialText)
        self.onCreate = onCreate
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextEditor(text: $text)
                    .padding(8)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary))
                Button("Створити PDF") { onCreate(text) }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .navigationTitle("Текст PDF")
        }
    }
}

enum RequestComposerLayoutPolicy {
    static let minimumLines = 1
    static let maximumLines = 6
}

private struct AdaptiveRequestComposer: View {
    @Binding var text: String
    let submit: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("type_command", text: $text, axis: .vertical)
                .lineLimit(RequestComposerLayoutPolicy.minimumLines...RequestComposerLayoutPolicy.maximumLines)
                .focused($isFocused)
                .textFieldStyle(.plain)
                .submitLabel(.send)
                .accessibilityIdentifier("assistant.input")

            Button(action: submitIfPossible) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(Text("send"))
            .accessibilityIdentifier("assistant.input.send")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 0.5)
        }
        .frame(maxWidth: 640)
        .accessibilityElement(children: .contain)
    }

    private func submitIfPossible() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        submit()
    }
}

#Preview { AssistantHomeView(model: AssistantViewModel()) }
