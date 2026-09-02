import SwiftUI

struct CompactResultCard: View {
    let state: AssistantResultState
    var onReportIssue: () -> Void = {}

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .recognized(let summary):
            card(summary, title: "request_recognized", tint: .blue)
        case .clarification(let summary):
            card(summary, title: "clarification_needed", tint: .orange)
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
                Button("clarification_needed", action: onReportIssue)
                    .font(.caption)
                    .accessibilityHint(Text("risk_informational"))
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
