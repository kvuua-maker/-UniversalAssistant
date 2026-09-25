import SwiftUI
import UIKit

struct IOS27DictationProbeEntryView: View {
    var body: some View {
#if IOS27_SPEECH_PROBE
        if #available(iOS 27.0, *) {
            IOS27DictationProbeView()
        } else {
            ContentUnavailableView("Requires iOS 27", systemImage: "waveform.badge.exclamationmark")
        }
#else
        ContentUnavailableView("Requires an Xcode 27 probe build", systemImage: "hammer")
#endif
    }
}

#if IOS27_SPEECH_PROBE
@available(iOS 27.0, *)
struct IOS27DictationProbeView: View {
    @StateObject private var controller = IOS27DictationProbeController()

    private let testPhrases = [
        "Відкрий Viber",
        "Відкрий Telegram",
        "Напиши мамі у WhatsApp я буду пізніше",
        "Проклади маршрут до Києва",
        "Відкрий PDF"
    ]

    var body: some View {
        List {
            Section("Device") {
                LabeledContent("iOS version", value: controller.iOSVersion)
                LabeledContent("Device model", value: controller.deviceModel)
            }

            Section("Locale and assets") {
                LabeledContent("Requested locale", value: IOS27DictationProbeController.requestedLocaleIdentifier)
                LabeledContent("Resolved locale", value: controller.resolvedLocaleIdentifier)
                LabeledContent("uk-UA supported", value: yesNo(controller.requestedLocaleSupported))
                LabeledContent("uk-UA installed", value: yesNo(controller.requestedLocaleInstalled))
                LabeledContent("Asset status", value: controller.assetStatus)
                LabeledContent("Asset download/install", value: controller.assetInstallation)
            }

            Section("Raw transcription") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Live transcript").font(.caption).foregroundStyle(.secondary)
                    Text(controller.liveTranscript.isEmpty ? "—" : controller.liveTranscript)
                        .textSelection(.enabled)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Final transcript").font(.caption).foregroundStyle(.secondary)
                    Text(controller.finalTranscript.isEmpty ? "—" : controller.finalTranscript)
                        .textSelection(.enabled)
                }
                LabeledContent("First-result latency", value: latency(controller.firstResultLatencyMilliseconds))
                LabeledContent("Final-result latency", value: latency(controller.finalResultLatencyMilliseconds))
            }

            Section("Runtime") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("LAST START STAGE").font(.caption).foregroundStyle(.secondary)
                    Text(controller.lastStartStage)
                        .font(.headline.monospaced())
                        .textSelection(.enabled)
                }
                if let error = controller.runtimeError {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                } else {
                    Text(controller.isRunning ? "RUNNING" : controller.isPreparing ? "PREPARING" : "IDLE")
                }
            }

            Section("Test phrases") {
                ForEach(Array(testPhrases.enumerated()), id: \.offset) { index, phrase in
                    Text("\(index + 1). \"\(phrase)\"")
                }
            }

            Section {
                Button("Start") { Task { await controller.start() } }
                    .disabled(controller.isRunning || controller.isPreparing)
                Button("Stop") { Task { await controller.stop() } }
                    .disabled(!controller.isRunning && !controller.isPreparing)
                Button("Copy Report") {
                    UIPasteboard.general.string = controller.reportText
                }
            }
        }
        .navigationTitle("iOS 27 Dictation Probe")
        .navigationBarTitleDisplayMode(.inline)
        .task { await controller.refreshCapabilities() }
        .onDisappear { Task { await controller.stop() } }
    }

    private func yesNo(_ value: Bool) -> String { value ? "YES" : "NO" }

    private func latency(_ value: Int?) -> String {
        value.map { "\($0) ms" } ?? "—"
    }
}
#endif
