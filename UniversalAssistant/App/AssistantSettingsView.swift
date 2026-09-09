import SwiftUI
import UIKit

struct AssistantSettingsView: View {
    @Bindable var model: AssistantViewModel
    @State private var preferences = PresentationPreferences()

    var body: some View {
        List {
            Section("AI / Mode") {
                LabeledContent("Base Mode", value: "On")
                LabeledContent("Connected AI", value: "Off")
            }
            Section("Language") { Text(Locale.current.localizedString(forIdentifier: Locale.current.identifier) ?? Locale.current.identifier) }
            Section("Appearance") {
                Button("Theme: \(preferences.appearance.rawValue)") { preferences.appearance = preferences.appearance == .automatic ? .dark : preferences.appearance == .dark ? .light : .automatic; persist() }
                Button("Accent: \(preferences.accent.rawValue)") { preferences.accent = preferences.accent == .purple ? .blue : .purple; persist() }
                Button("Animation: \(preferences.animationLevel.rawValue)") { preferences.animationLevel = preferences.animationLevel == .system ? .reduced : .system; persist() }
            }
            Section("Voice & Interaction") {
                Button("Voice responses: \(preferences.voiceOutput.rawValue)") { preferences.voiceOutput = preferences.voiceOutput == .contextual ? .screenOnly : .contextual; persist() }
                Button(model.voiceInputEnabled ? "Disable voice input" : "Enable voice input") { model.setVoiceInputEnabled(!model.voiceInputEnabled) }
                Button("Скопіювати діагностику") {
                    UIPasteboard.general.string = model.voiceDiagnosticReport()
                }
                .accessibilityIdentifier("settings.copy-voice-diagnostics")
            }
            Section("Permissions") {
                Button("Увімкнути proactive-сповіщення") {
                    Task { await model.enableProactiveNotifications() }
                }
                .accessibilityIdentifier("settings.enable-proactive-notifications")
                if let url = URL(string: UIApplication.openSettingsURLString) { Link("iPhone Permissions", destination: url) }
            }
            Section("Privacy & Data") { Text("On-device preferences contain no raw command history.").foregroundStyle(.secondary) }
            Section("About") { LabeledContent("App", value: "UniversalAssistant") }
        }
        .navigationTitle("Settings")
        .onAppear { preferences = model.presentationPreferences }
    }

    private func persist() { model.savePresentationPreferences(preferences) }
}

extension AppAccent {
    var color: Color {
        switch self { case .purple: .purple; case .blue: .blue; case .cyan: .cyan; case .green: .green; case .amber: .orange; case .pink: .pink }
    }
}
