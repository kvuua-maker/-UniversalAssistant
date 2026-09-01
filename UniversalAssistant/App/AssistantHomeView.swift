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
                    .accessibilityLabel(model.isListening ? Text("stop_listening") : Text("start_listening"))
                    Text(model.statusText).font(.headline).accessibilityIdentifier("assistant.status")
                    RecordingStatusPill(state: model.recorder.state)
                    CompactResultCard(state: model.resultState)
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
            }
            .tabItem { Label("home", systemImage: "house") }
            ContentUnavailableView("my_tasks", systemImage: "checklist")
                .tabItem { Label("my_tasks", systemImage: "checklist") }
            ContentUnavailableView("favorites", systemImage: "star")
                .tabItem { Label("favorites", systemImage: "star") }
        }
    }
}

#Preview { AssistantHomeView(model: AssistantViewModel()) }
