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
                    .accessibilityLabel(model.isListening ? "Stop listening" : "Start listening")
                    Text(model.statusText).font(.headline).accessibilityIdentifier("assistant.status")
                    Spacer()
                    TextField("Або напишіть", text: $model.input)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.go)
                        .onSubmit(model.submit)
                        .accessibilityIdentifier("assistant.input")
                }
                .padding()
                .navigationTitle("UniversalAssistant")
            }
            .tabItem { Label("Home", systemImage: "house") }
            ContentUnavailableView("My Tasks", systemImage: "checklist")
                .tabItem { Label("My Tasks", systemImage: "checklist") }
            ContentUnavailableView("Favorites", systemImage: "star")
                .tabItem { Label("Favorites", systemImage: "star") }
        }
    }
}

#Preview { AssistantHomeView(model: AssistantViewModel()) }
