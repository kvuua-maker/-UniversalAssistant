import SwiftUI

struct WeatherResultCard: View {
    let snapshot: WeatherSnapshot
    var onReportIssue: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: selectedDaily?.symbolName ?? snapshot.current.symbolName)
                .font(.largeTitle)
                .foregroundStyle(.blue)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 5) {
                Text(snapshot.locationLabel ?? String(localized: "weather_current_location", table: "Weather"))
                    .font(.headline)
                if let requestedDate = snapshot.requestedDate {
                    Text(requestedDate.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if let selectedDaily {
                    Text("\(selectedDaily.lowTemperatureCelsius.formatted(.number.precision(.fractionLength(0))))…\(selectedDaily.highTemperatureCelsius.formatted(.number.precision(.fractionLength(0)))) °C")
                        .font(.system(.title, design: .rounded, weight: .semibold))
                } else {
                    (Text(snapshot.current.temperatureCelsius,
                          format: .number.precision(.fractionLength(0))) + Text(" °C"))
                        .font(.system(.title, design: .rounded, weight: .semibold))
                }
                Text(selectedDaily?.condition ?? snapshot.current.condition)
                    .font(.subheadline)
                if selectedDaily == nil {
                    Text(String(format: String(localized: "weather_feels_like_format", table: "Weather"),
                                snapshot.current.apparentTemperatureCelsius))
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        .accessibilityIdentifier("assistant.weather-result")
    }

    private var selectedDaily: DailyWeatherValue? {
        guard let target = snapshot.requestedDate else { return nil }
        let calendar = Calendar.autoupdatingCurrent
        return snapshot.daily.min {
            abs(calendar.startOfDay(for: $0.date).timeIntervalSince(calendar.startOfDay(for: target))) <
                abs(calendar.startOfDay(for: $1.date).timeIntervalSince(calendar.startOfDay(for: target)))
        }
    }
}
