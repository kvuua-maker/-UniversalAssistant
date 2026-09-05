import SwiftUI

struct CompactResultCard: View {
    let state: AssistantResultState
    var onReportIssue: () -> Void = {}

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
                Text("web_search_ready").font(.headline)
                Text(result.query).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                Link("web_search_open", destination: result.destination).buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("assistant.web-search.open")
            }.padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityIdentifier("assistant.web-search-result")
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
