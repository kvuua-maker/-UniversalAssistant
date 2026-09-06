import SwiftUI

struct CompactResultCard: View {
    let state: AssistantResultState
    var onReportIssue: () -> Void = {}
    var onScannerAction: (ScannerProductionResult) -> Void = { _ in }
    var onOCRAction: (OCRProductionResult, OCRResultAction) -> Void = { _, _ in }
    var onTranslationAction: (TranslationProductionResult, OCRResultAction) -> Void = { _, _ in }

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .processing:
            HStack(spacing: 12) {
                ProgressView()
                Text("processing").font(.headline)
            }
            .padding(16)
            .accessibilityIdentifier("assistant.processing")
        case .recognized(let summary):
            card(summary, title: "request_recognized", tint: .blue)
        case .weather(let snapshot):
            WeatherResultCard(snapshot: snapshot, onReportIssue: onReportIssue)
        case .webHandoff(let result):
            VStack(alignment: .leading, spacing: 10) {
                Text(handoffTitle(result.kind)).font(.headline)
                Text(result.query).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                Link(handoffAction(result.kind), destination: result.destination).buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("assistant.web-search.open")
            }.padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityIdentifier("assistant.web-search-result")
        case .scanner(let result):
            VStack(alignment: .leading, spacing: 10) {
                Text(result.observedType == "qr" ? "QR-код" : "Штрихкод").font(.headline)
                Text(result.observedValue).font(.subheadline).textSelection(.enabled)
                Button(result.route.requiresConfirmation ? "Підтвердити дію" : "Виконати") { onScannerAction(result) }.buttonStyle(.borderedProminent)
            }.padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous)).accessibilityIdentifier("assistant.scanner-result")
        case .ocr(let result):
            VStack(alignment: .leading, spacing: 10) {
                Text("Розпізнаний текст").font(.headline)
                Text(result.recognizedText).font(.subheadline).textSelection(.enabled).lineLimit(8)
                HStack { ForEach(result.actions, id: \.self) { action in Button(ocrActionTitle(action)) { onOCRAction(result, action) }.buttonStyle(.bordered) } }
            }.padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous)).accessibilityIdentifier("assistant.ocr-result")
        case .translation(let result):
            VStack(alignment: .leading, spacing: 10) {
                Text("Переклад").font(.headline)
                Text(result.translatedText).font(.subheadline).textSelection(.enabled)
                HStack {
                    Button("Копіювати") { onTranslationAction(result, .copy) }.buttonStyle(.bordered)
                    Button("Поділитися") { onTranslationAction(result, .share) }.buttonStyle(.bordered)
                }
            }.padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous)).accessibilityIdentifier("assistant.translation-result")
        case .deterministic(let result):
            VStack(alignment: .leading, spacing: 10) {
                Text(result.primaryAnswer).font(.headline)
                ForEach(result.facts.prefix(5)) { fact in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fact.label).font(.subheadline.weight(.semibold))
                        if let value = fact.value { Text(value).font(.subheadline) }
                        if let source = fact.source { Text(source).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                ForEach(result.actions.prefix(3)) { action in
                    if let destination = action.destination { Link(action.title, destination: destination).buttonStyle(.bordered) }
                }
                ForEach(result.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            }.padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityIdentifier("assistant.deterministic-result")
        case .eventKit(let result):
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: result.kind == .calendar ? "calendar" : "checkmark.circle.fill")
                    .font(.title2).foregroundStyle(.blue).frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.title).font(.headline)
                    Text(result.detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }.padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityIdentifier("assistant.eventkit-result")
        case .clarification(let summary):
            card(summary, title: "clarification_needed", tint: .orange)
        case .actionRequired(let value):
            VStack(alignment: .leading, spacing: 10) {
                Text(value.prompt).font(.headline)
                ForEach(value.choices, id: \.self) { Text($0).font(.subheadline) }
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityIdentifier("assistant.action-required")
        case .failure(let value):
            VStack(alignment: .leading, spacing: 6) {
                Text(value.message).font(.headline)
                if let recovery = value.recoveryAction { Text(recovery).font(.subheadline) }
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityIdentifier("assistant.failure")
        case .expanded(let summary):
            card(summary, title: "request_recognized", tint: .blue)
        }
    }

    private func ocrActionTitle(_ action: OCRResultAction) -> String {
        switch action { case .copy: "Копіювати"; case .share: "Поділитися"; case .translate: "Перекласти" }
    }

    private func handoffTitle(_ kind: HandoffKind) -> LocalizedStringKey {
        switch kind {
        case .webSearch: "web_search_ready"
        case .navigation: "navigation_ready"
        case .system: "system_handoff_ready"
        }
    }

    private func handoffAction(_ kind: HandoffKind) -> LocalizedStringKey {
        switch kind {
        case .webSearch: "web_search_open"
        case .navigation: "navigation_open"
        case .system: "system_handoff_open"
        }
    }

    private func card(_ summary: ResultSummary, title: LocalizedStringKey, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: summary.symbolName)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(summary.request)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if summary.risk != .informational {
                    Text(riskKey(summary.risk))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                }
                Button(action: onReportIssue) {
                    Text("feedback_wrong_result", tableName: "Feedback")
                }
                    .font(.caption)
                    .accessibilityHint(Text("feedback_privacy_hint", tableName: "Feedback"))
                    .accessibilityIdentifier("assistant.feedback.wrong-result")
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("assistant.result")
    }

    private func riskKey(_ risk: ActionRisk) -> LocalizedStringKey {
        switch risk {
        case .informational: "risk_informational"
        case .reversible: "risk_reversible"
        case .consequential: "risk_consequential"
        case .emergency: "risk_emergency"
        }
    }
}
