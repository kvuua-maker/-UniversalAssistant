import SwiftUI
import UIKit

private struct DiagnosticExportItem: Identifiable {
    let url: URL
    var id: String { url.path }
}

struct AssistantSettingsView: View {
    @Bindable var model: AssistantViewModel
    @State private var preferences = PresentationPreferences()
    @State private var diagnosticStatus = PhysicalDiagnosticLocalStore.shared.status()
    @State private var diagnosticExport: DiagnosticExportItem?
    @State private var diagnosticExportError: String?
    @State private var detailedDiagnostics = LocalVoiceDiagnosticReport.shared.detailedDiagnosticsEnabled

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
            Section("Діагностика UniversalAssistant") {
                LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "невідомо")
                LabeledContent("Діагностика активна", value: diagnosticStatus.diagnosticsActive ? "Так" : "Ні")
                LabeledContent("SessionID", value: diagnosticStatus.diagnosticSessionID?.uuidString ?? LocalVoiceDiagnosticReport.shared.diagnosticSessionIdentifier.uuidString)
                LabeledContent("Записаних запитів", value: String(diagnosticStatus.recordedRequests))
                LabeledContent("Очікують надсилання", value: String(diagnosticStatus.pendingUploads))
                LabeledContent("Завантажено подій", value: String(diagnosticStatus.uploadedEvents))
                LabeledContent("Останній запит", value: diagnosticStatus.lastRequestID?.uuidString ?? "Немає")
                LabeledContent("Останній етап", value: diagnosticStatus.lastStage ?? "Немає")
                LabeledContent("Остання аномалія", value: diagnosticStatus.lastAnomaly?.anomalyClass.rawValue ?? "Немає")
                LabeledContent("Останнє аварійне завершення", value: diagnosticStatus.lastUncleanTermination?.formatted() ?? "Немає")
                LabeledContent("Apple crash diagnostic", value: appleDiagnosticStatus)
                LabeledContent("VPS delivery", value: deliveryStatusText)
                Toggle("Детальна мовна діагностика", isOn: $detailedDiagnostics)
                    .onChange(of: detailedDiagnostics) { _, value in
                        LocalVoiceDiagnosticReport.shared.detailedDiagnosticsEnabled = value
                    }
                    .accessibilityIdentifier("settings.detailed-diagnostics")
                Text("Зберігаються partial/final/normalized transcript і bounded audio команди з того самого Speech stream. Audio поки залишається локально.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Оновити статус") { refreshDiagnostics() }
                    .accessibilityIdentifier("settings.refresh-diagnostics")
                Button("Експортувати діагностику") { exportDiagnostics() }
                    .accessibilityIdentifier("settings.export-diagnostics")
                if let diagnosticExportError {
                    Text(diagnosticExportError).font(.footnote).foregroundStyle(.red)
                }
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
        .onAppear {
            preferences = model.presentationPreferences
            detailedDiagnostics = LocalVoiceDiagnosticReport.shared.detailedDiagnosticsEnabled
            refreshDiagnostics()
        }
        .sheet(item: $diagnosticExport) { item in
            SystemShareSheet(items: [item.url])
        }
    }

    private var appleDiagnosticStatus: String {
        if diagnosticStatus.appleDiagnosticCount > 0 { return "Доступна" }
        if diagnosticStatus.lastUncleanTermination != nil { return "Очікується" }
        return "Немає"
    }

    private var deliveryStatusText: String {
        switch diagnosticStatus.deliveryStatus {
        case .localEvents: "Локально"
        case .pendingUpload: "Очікує надсилання"
        case .uploaded: "Завантажено"
        case .serverRejected: "Відхилено сервером"
        case .retrying: "Повторна спроба"
        }
    }

    private func refreshDiagnostics() {
        diagnosticStatus = PhysicalDiagnosticLocalStore.shared.status()
    }

    private func exportDiagnostics() {
        diagnosticExportError = nil
        Task {
            do {
                let url = try await Task.detached(priority: .utility) {
                    try DiagnosticExportBuilder.makeBuild32Package()
                }.value
                diagnosticExport = .init(url: url)
                refreshDiagnostics()
            } catch {
                diagnosticExportError = "Не вдалося створити пакет діагностики."
            }
        }
    }

    private func persist() { model.savePresentationPreferences(preferences) }
}

extension AppAccent {
    var color: Color {
        switch self { case .purple: .purple; case .blue: .blue; case .cyan: .cyan; case .green: .green; case .amber: .orange; case .pink: .pink }
    }
}
