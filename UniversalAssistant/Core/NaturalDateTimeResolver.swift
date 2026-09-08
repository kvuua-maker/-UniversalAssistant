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
        if let interval = relativeInterval(in: text) {
            return .resolved(.init(instant: reference.addingTimeInterval(interval), timeZoneIdentifier: timeZone.identifier, precision: .minute))
        }
        guard let dayOffset = relativeDayOffset(in: text) else { return .unresolved }

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        guard let targetDay = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: reference)) else {
            return .unresolved
        }

        let time = explicitTime(in: text) ?? spokenTime(in: text)
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

    private func relativeInterval(in text: String) -> TimeInterval? {
        let pattern = #"(?:через|за|in)\s+(\d+)\s*(хвилин(?:у|и)?|хв|минут(?:у|ы)?|мин|minutes?|mins?|секунд(?:у|и)?|сек|seconds?|secs?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let amountRange = Range(match.range(at: 1), in: text), let amount = Int(text[amountRange]),
              let unitRange = Range(match.range(at: 2), in: text) else { return nil }
        let unit = String(text[unitRange])
        return TimeInterval(amount * ((unit.hasPrefix("сек") || unit.hasPrefix("sec")) ? 1 : 60))
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

    private func spokenTime(in text: String) -> (hour: Int, minute: Int)? {
        let hours: [(Int, [String])] = [
            (23, ["двадцять трет", "двадцать трет"]), (22, ["двадцять друг", "двадцать втор"]),
            (21, ["двадцять перш", "двадцать перв"]), (20, ["двадцят", "двадцат"]),
            (19, ["дев'ятнадцят", "девятнадцат"]), (18, ["вісімнадцят", "восемнадцат"]),
            (17, ["сімнадцят", "семнадцат"]), (16, ["шістнадцят", "шестнадцат"]),
            (15, ["п'ятнадцят", "пятнадцят", "пятнадцат"]), (14, ["чотирнадцят", "четырнадцат"]),
            (13, ["тринадцят", "тринадцат"]), (12, ["дванадцят", "двенадцат"]),
            (11, ["одинадцят", "одиннадцат"]), (10, ["десят"]),
            (9, ["дев'ят", "девят"]), (8, ["восьм", "восем"]),
            (7, ["сьом", "седьм"]), (6, ["шост", "шест"]),
            (5, ["п'ят", "пят"]), (4, ["четверт", "чотир"]),
            (3, ["трет"]), (2, ["друг", "другій", "втор"]),
            (1, ["перш", "перв"]), (0, ["опівноч", "полноч"])
        ]
        guard text.contains(" о ") || text.contains(" об ") || text.contains(" в ") || text.hasSuffix("ій") || text.hasSuffix("ой") else { return nil }
        guard let hour = hours.first(where: { entry in entry.1.contains(where: text.contains) })?.0 else { return nil }
        let minute = text.contains("половин") ? 30 : text.contains("чверт") || text.contains("четверть") ? 15 : 0
        return (hour, minute)
    }

    private func explicitTime(in text: String) -> (hour: Int, minute: Int)? {
        // A clock token is structurally stronger than an earlier quantity
        // (for example an event duration). Resolve it before the general
        // spoken/bare-hour form so quantities cannot steal the time role.
        let clockPattern = #"(?<!\d)(\d{1,2})[:.](\d{2})\b"#
        if let clockRegex = try? NSRegularExpression(pattern: clockPattern),
           let clockMatch = clockRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let hourRange = Range(clockMatch.range(at: 1), in: text),
           let minuteRange = Range(clockMatch.range(at: 2), in: text),
           let hour = Int(text[hourRange]), let minute = Int(text[minuteRange]),
           (0...23).contains(hour), (0...59).contains(minute) {
            return (hour, minute)
        }

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
