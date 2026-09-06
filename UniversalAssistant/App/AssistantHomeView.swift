import MessageUI
import SwiftUI

struct AssistantHomeView: View {
    @Bindable var model: AssistantViewModel

    var body: some View {
        TabView {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 28) {
                        Spacer(minLength: 24)
                        Button(action: model.toggleListening) {
                            Image(systemName: model.isListening ? "waveform.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 112))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                    }
                        .disabled(!model.voiceInputEnabled)
                        .accessibilityLabel(model.isListening ? Text("stop_listening") : Text("start_listening"))
                    Toggle("voice_input_enabled", isOn: Binding(
                        get: { model.voiceInputEnabled }, set: { model.setVoiceInputEnabled($0) }
                    ))
                    .accessibilityIdentifier("assistant.voice-input-toggle")
                    Text(model.statusText).font(.headline).accessibilityIdentifier("assistant.status")
                    if model.shouldOfferSettings,
                       let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        Link("settings", destination: settingsURL)
                            .accessibilityIdentifier("assistant.permission-settings")
                    }
                    RecordingStatusPill(state: model.recorder.state)
                    CompactResultCard(state: model.resultState, onReportIssue: {
                        Task { await model.reportWrongResult() }
                    }, onScannerAction: model.performScannerAction)
                        .frame(maxWidth: 520)
                        Spacer(minLength: 24)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    AdaptiveRequestComposer(text: $model.input, submit: model.submit)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(.bar)
                }
                .navigationTitle("UniversalAssistant")
                .toolbar {
                    NavigationLink(destination: QuickLaunchView(capabilities: .init(
                        actionButton: .unavailable, backTap: .available, appShortcut: .available,
                        homeScreenShortcut: .available, assistiveTouch: .available))) {
                        Image(systemName: "bolt.circle")
                    }.accessibilityLabel("Швидкий запуск")
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
        .sheet(item: Binding(
            get: { model.capabilityPresentation },
            set: { if $0 == nil { model.dismissCapabilityPresentation() } }
        )) { presentation in
            switch presentation {
            case .camera:
                SystemCameraCapture { _ in model.dismissCapabilityPresentation() }
            case .scanner:
                LiveCodeScannerView(onResult: model.handleScannedCode, onUnavailable: model.handleScannerUnavailable)
            case .documents:
                AuthorizedDocumentPicker { _ in model.dismissCapabilityPresentation() }
            case let .share(value):
                SystemShareSheet(items: [value])
            case let .contactImport(data):
                VCardImportConfirmationView(data: data, onComplete: model.dismissCapabilityPresentation)
            case let .message(recipients, body):
                if MFMessageComposeViewController.canSendText() {
                    SystemMessageComposer(recipients: recipients, body: body) { _ in model.dismissCapabilityPresentation() }
                } else {
                    Text("request_unavailable")
                }
            }
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
