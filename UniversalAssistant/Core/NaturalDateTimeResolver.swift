import Foundation

struct ResolvedNaturalDateTime: Equatable, Sendable {
    let instant: Date
    let timeZoneIdentifier: String
    let precision: Precision

    enum Precision: String, Sendable { case day, minute }
}

enum NaturalDateTimeResolution: Equatable, Sendable {
    case resolved(ResolvedNaturalDateTime)
    case unresolved
}

struct NaturalDateTimeResolver: Sendable {
    func resolve(
        _ input: String,
        locale: Locale,
        timeZone: TimeZone,
        relativeTo reference: Date
    ) -> NaturalDateTimeResolution {
        let text = input.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
        guard let dayOffset = relativeDayOffset(in: text) else { return .unresolved }

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        guard let targetDay = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: reference)) else {
            return .unresolved
        }

        let time = explicitTime(in: text)
        let instant: Date
        if let time {
            guard let value = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: targetDay) else {
                return .unresolved
            }
            instant = value
        } else {
            instant = targetDay
        }
        return .resolved(.init(
            instant: instant,
            timeZoneIdentifier: timeZone.identifier,
            precision: time == nil ? .day : .minute
        ))
    }

    private func relativeDayOffset(in text: String) -> Int? {
        let phrases: [(String, Int)] = [
            ("післязавтра", 2), ("послезавтра", 2), ("day after tomorrow", 2),
            ("ubermorgen", 2), ("apres-demain", 2),
            ("завтра", 1), ("tomorrow", 1), ("morgen", 1), ("demain", 1),
            ("сьогодні", 0), ("сегодня", 0), ("today", 0), ("heute", 0), ("aujourd'hui", 0)
        ]
        return phrases.first(where: { text.contains($0.0) })?.1
    }

    private func explicitTime(in text: String) -> (hour: Int, minute: Int)? {
        let pattern = #"(?<!\d)(?:о|об|в|at|um|a)?\s*(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm)?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let hourRange = Range(match.range(at: 1), in: text),
              var hour = Int(text[hourRange]) else { return nil }
        let minute: Int
        if match.range(at: 2).location != NSNotFound,
           let range = Range(match.range(at: 2), in: text),
           let value = Int(text[range]) {
            minute = value
        } else {
            minute = 0
        }
        if match.range(at: 3).location != NSNotFound,
           let range = Range(match.range(at: 3), in: text) {
            let marker = text[range]
            if marker == "pm" { hour += hour == 12 ? 0 : 12 }
            if marker == "am" { hour = hour == 12 ? 0 : hour }
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }
}
