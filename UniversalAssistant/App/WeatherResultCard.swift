import SwiftUI

struct WeatherResultCard: View {
    let snapshot: WeatherSnapshot
    var onReportIssue: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: snapshot.current.symbolName)
                .font(.largeTitle)
                .foregroundStyle(.blue)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 5) {
                Text(snapshot.locationLabel ?? String(localized: "weather_current_location", table: "Weather"))
                    .font(.headline)
                (Text(snapshot.current.temperatureCelsius,
                      format: .number.precision(.fractionLength(0))) + Text(" °C"))
                    .font(.system(.title, design: .rounded, weight: .semibold))
                Text(snapshot.current.condition)
                    .font(.subheadline)
                Text(String(format: String(localized: "weather_feels_like_format", table: "Weather"),
                            snapshot.current.apparentTemperatureCelsius))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: String(localized: "weather_source_format", table: "Weather"), snapshot.source))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
        .accessibilityIdentifier("assistant.weather-result")
    }
}
