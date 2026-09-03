import SwiftUI

struct AssistantHomeView: View {
    @Bindable var model: AssistantViewModel

    var body: some View {
        TabView {
            NavigationStack {
                VStack(spacing: 28) {
                    Spacer()
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
                    })
                        .frame(maxWidth: 520)
                    Spacer()
                    TextField("type_command", text: $model.input)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.go)
                        .onSubmit(model.submit)
                        .accessibilityIdentifier("assistant.input")
                }
                .padding()
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
    }
}

#Preview { AssistantHomeView(model: AssistantViewModel()) }
