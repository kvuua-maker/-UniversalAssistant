import SwiftUI
import UIKit

/// Live view of the voice → intent → URL chain, plus a direct URL test.
struct DiagnosticsView: View {
    private var diagnostics: RuntimeDiagnostics { RuntimeDiagnostics.shared }
    @Environment(\.dismiss) private var dismiss
    @State private var lastResult: String?

    private static let testLinks: [URL] = ["tg://", "viber://", "whatsapp://app", "spotify://"]
        .compactMap { URL(string: $0) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Скопіювати лог") {
                        UIPasteboard.general.string = diagnostics.copyableText
                        lastResult = "Лог скопійовано (\(diagnostics.entries.count) записів)"
                    }
                    ShareLink(item: diagnostics.copyableText) { Text("Поділитися логом") }
                    Button("Очистити", role: .destructive) { diagnostics.clear() }
                }

                Section("Тест URL (без голосу)") {
                    ForEach(Self.testLinks, id: \.absoluteString) { url in
                        Button(url.absoluteString) { test(url) }
                    }
                    if let lastResult {
                        Text(lastResult).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Живий лог") {
                    if diagnostics.entries.isEmpty {
                        Text("Порожньо — скажіть або введіть команду")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(diagnostics.entries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.kind).font(.caption2).foregroundStyle(.secondary)
                            Text(entry.text).font(.footnote).textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle("Діагностика")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }

    private func test(_ url: URL) {
        let scheme = url.scheme?.lowercased() ?? "-"
        let allowed = UIApplication.shared.canOpenURL(url)
        diagnostics.log("test", "\(url.absoluteString) canOpenURL=\(allowed)")
        guard allowed else {
            lastResult = "\(scheme):// не дозволено: застосунок не встановлено або схема відсутня в LSApplicationQueriesSchemes"
            return
        }
        UIApplication.shared.open(url, options: [:]) { opened in
            Task { @MainActor in
                diagnostics.log("test", "\(url.absoluteString) open -> \(opened ? "opened" : "rejected")")
                lastResult = opened ? "Відкрито \(scheme)://" : "iOS відхилив відкриття \(scheme)://"
            }
        }
    }
}
