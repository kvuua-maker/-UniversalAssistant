import Foundation

/// Produces one typed temporal interpretation before capability selection.
/// Numbers have already passed through `StructuredNumberNormalizer`, so every
/// consumer sees the same duration/date/clock roles for typed and voice input.
struct CanonicalTemporalAnalyzer: Sendable {
    nonisolated(unsafe) private static let regexCache = NSCache<NSString, NSRegularExpression>()

    enum Kind: String, Equatable, Sendable {
        case duration
        case relativeDeadline = "relative_deadline"
        case calendarDay = "calendar_day"
        case clockTime = "clock_time"
        case dateTime = "date_time"
        case ambiguous
    }

    struct Analysis: Equatable, Sendable {
        let kind: Kind
        let durationSeconds: Int?
        let relativeIntervalSeconds: Int?
        let relativeDayOffset: Int?
        let weekday: Int?
        let calendarYear: Int?
        let calendarMonth: Int?
        let calendarDay: Int?
        let hour: Int?
        let minute: Int?
        let dayPeriod: String?
        let confidence: Double
        let evidence: Set<String>
        let requiresClarification: Bool
    }

    func analyze(
        normalized text: String,
        object: CanonicalSemanticFrame.Object?
    ) -> Analysis? {
        let duration = durationRole(in: text)
        let day = dayRole(in: text)
        let date = absoluteDate(in: text)
        let clock = clockRole(in: text, object: object)
        let period = dayPeriod(in: text)
        guard duration != nil || day != nil || date != nil || clock != nil || period != nil else { return nil }

        var evidence = Set<String>()
        if duration != nil { evidence.insert("quantity_unit") }
        if duration?.isRelativeDeadline == true { evidence.insert("relative_preposition") }
        if day != nil { evidence.insert(day?.weekday == nil ? "relative_day" : "weekday") }
        if date != nil { evidence.insert("calendar_date") }
        if clock != nil { evidence.insert(clock?.evidence ?? "clock") }
        if period != nil { evidence.insert("day_period") }

        let incompatible: Bool = {
            guard let duration else { return false }
            if object == .timer { return clock != nil }
            if object == .alarm { return true }
            return duration.isRelativeDeadline && clock != nil
        }()
        if incompatible { evidence.insert("incompatible_temporal_roles") }

        let kind: Kind
        if incompatible || date?.ambiguous == true || clock?.ambiguous == true {
            kind = .ambiguous
        } else if duration?.isRelativeDeadline == true {
            kind = .relativeDeadline
        } else if object == .timer, duration != nil {
            kind = .duration
        } else if date != nil || day != nil {
            kind = clock == nil ? .calendarDay : .dateTime
        } else if clock != nil {
            kind = .clockTime
        } else if duration != nil {
            kind = .duration
        } else {
            kind = .calendarDay
        }

        let confidenceCandidates = [duration?.confidence, day?.confidence, date?.confidence, clock?.confidence]
            .compactMap { $0 }
        let confidence = incompatible ? 0.35 : (confidenceCandidates.min() ?? 0.82)
        return .init(
            kind: kind,
            durationSeconds: duration?.seconds,
            relativeIntervalSeconds: duration?.isRelativeDeadline == true ? duration?.seconds : nil,
            relativeDayOffset: day?.offset,
            weekday: day?.weekday,
            calendarYear: date?.year,
            calendarMonth: date?.month,
            calendarDay: date?.day,
            hour: clock?.hour,
            minute: clock?.minute,
            dayPeriod: period,
            confidence: confidence,
            evidence: evidence,
            requiresClarification: incompatible || date?.ambiguous == true || clock?.ambiguous == true
        )
    }

    private struct DurationMatch {
        let seconds: Int
        let isRelativeDeadline: Bool
        let confidence: Double
    }

    private func durationRole(in text: String) -> DurationMatch? {
        let unit = #"(секунд\p{L}*|сек|seconds?|secs?|хвилин\p{L}*|хв|минут\p{L}*|мин|minutes?|mins?|годин\p{L}*|час\p{L}*|hours?|hrs?)"#
        let numbered = #"\b([0-9]+(?:[.,][0-9]+)?)\s*"# + unit + #"\b"#
        if let match = firstMatch(numbered, in: text),
           let amountText = capture(1, from: match, in: text),
           let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")),
           let unitText = capture(2, from: match, in: text) {
            let seconds = Int((amount * multiplier(for: unitText)).rounded())
            guard seconds > 0, let range = Range(match.range, in: text) else { return nil }
            let prefix = String(text[..<range.lowerBound]).lowercased()
            return .init(seconds: seconds, isRelativeDeadline: hasRelativeMarker(atEndOf: prefix), confidence: 0.97)
        }

        // A singular unit without a quantity is a productive grammatical form
        // ("for a minute" / "на хвилину"), not a memorized command phrase.
        let implicit = #"\b(?:на|for|через|за|in)\s+"# + unit + #"\b"#
        guard let match = firstMatch(implicit, in: text),
              let unitText = capture(1, from: match, in: text) else { return nil }
        let marker = capture(0, from: match, in: text)?.split(separator: " ").first.map(String.init) ?? ""
        return .init(
            seconds: Int(multiplier(for: unitText)),
            isRelativeDeadline: ["через", "за", "in"].contains(marker.lowercased()),
            confidence: 0.92
        )
    }

    private func multiplier(for unit: String) -> Double {
        let value = unit.lowercased()
        if value.hasPrefix("сек") || value.hasPrefix("sec") { return 1 }
        if value.hasPrefix("год") || value.hasPrefix("час") || value.hasPrefix("hour") || value.hasPrefix("hr") { return 3_600 }
        return 60
    }

    private func hasRelativeMarker(atEndOf prefix: String) -> Bool {
        guard let marker = prefix.split(whereSeparator: { !$0.isLetter }).last else { return false }
        return ["через", "за", "in"].contains(marker.lowercased())
    }

    private struct DayMatch {
        let offset: Int?
        let weekday: Int?
        let confidence: Double
    }

    private func dayRole(in text: String) -> DayMatch? {
        let offsets: [(String, Int)] = [
            ("післязавтра", 2), ("послезавтра", 2), ("day after tomorrow", 2),
            ("завтра", 1), ("tomorrow", 1),
            ("сьогодні", 0), ("сегодня", 0), ("today", 0),
            ("вчора", -1), ("вчера", -1), ("yesterday", -1)
        ]
        if let value = offsets.first(where: { containsWordOrPhrase($0.0, in: text) }) {
            return .init(offset: value.1, weekday: nil, confidence: 0.98)
        }

        let weekdays: [(Int, [String])] = [
            (2, ["понеділ", "понедель", "monday"]),
            (3, ["вівтор", "вторник", "tuesday"]),
            (4, ["серед", "сред", "wednesday"]),
            (5, ["четвер", "thursday"]),
            (6, ["п'ятниц", "пятниц", "friday"]),
            (7, ["субот", "суббот", "saturday"]),
            (1, ["неділ", "воскрес", "sunday"])
        ]
        let words = text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        guard let weekday = weekdays.first(where: { entry in
            entry.1.contains { root in
                words.contains { word in
                    guard word.hasPrefix(root) else { return false }
                    // Ukrainian/Russian "серед/сред" are also productive
                    // prepositions ("among"). A weekday interpretation needs
                    // an inflected weekday token, never the bare preposition.
                    if root == "серед" || root == "сред" {
                        return word.count > root.count
                    }
                    return true
                }
            }
        })?.0 else { return nil }
        let explicitNext = ["наступн", "следующ", "next"].contains(where: text.contains)
        return .init(offset: nil, weekday: weekday, confidence: explicitNext ? 0.95 : 0.82)
    }

    private struct DateMatch {
        let year: Int?
        let month: Int
        let day: Int
        let confidence: Double
        let ambiguous: Bool
    }

    private func absoluteDate(in text: String) -> DateMatch? {
        let iso = #"\b(20\d{2})[-/](0?[1-9]|1[0-2])[-/](0?[1-9]|[12]\d|3[01])\b"#
        if let match = firstMatch(iso, in: text),
           let year = integerCapture(1, match, text),
           let month = integerCapture(2, match, text),
           let day = integerCapture(3, match, text) {
            return .init(year: year, month: month, day: day, confidence: 0.99, ambiguous: false)
        }
        let named = #"\b(0?[1-9]|[12]\d|3[01])\s+([\p{L}.'’]+)(?:\s+(20\d{2}))?\b"#
        if let match = firstMatch(named, in: text),
           let day = integerCapture(1, match, text),
           let name = capture(2, from: match, in: text),
           let month = monthNumber(for: name) {
            return .init(year: integerCapture(3, match, text), month: month, day: day, confidence: 0.97, ambiguous: false)
        }
        let local = #"\b(0?[1-9]|[12]\d|3[01])([./-])(0?[1-9]|1[0-2])(?:\2(20\d{2}))?\b"#
        guard let match = firstMatch(local, in: text),
              let day = integerCapture(1, match, text),
              let month = integerCapture(3, match, text) else { return nil }
        let year = integerCapture(4, match, text)
        let raw = capture(0, from: match, in: text) ?? ""
        let markerPattern = #"(?:^|\s)(?:на|for|date)\s+"# + NSRegularExpression.escapedPattern(for: raw)
        let marker = text.range(of: markerPattern, options: [.regularExpression, .caseInsensitive]) != nil
        let couldBeClock = year == nil && day <= 23 && raw.contains(".")
        return .init(year: year, month: month, day: day, confidence: marker || year != nil ? 0.96 : 0.84, ambiguous: couldBeClock && !marker)
    }

    private func monthNumber(for raw: String) -> Int? {
        let value = raw.lowercased().folding(options: [.diacriticInsensitive], locale: .current)
        let roots: [(Int, [String])] = [
            (1, ["січ", "январ", "januar"]),
            (2, ["лют", "феврал", "februar"]),
            (3, ["берез", "март", "march"]),
            (4, ["квіт", "апрел", "april"]),
            (5, ["трав", "мая", "май", "may"]),
            (6, ["черв", "июн", "june"]),
            (7, ["лип", "июл", "july"]),
            (8, ["серп", "август", "august"]),
            (9, ["верес", "сентябр", "september"]),
            (10, ["жовт", "октябр", "october"]),
            (11, ["листопад", "ноябр", "november"]),
            (12, ["груд", "декабр", "december"])
        ]
        return roots.first { _, variants in variants.contains(where: value.hasPrefix) }?.0
    }

    private struct ClockMatch {
        let hour: Int
        let minute: Int
        let confidence: Double
        let evidence: String
        let ambiguous: Bool
    }

    private func clockRole(in text: String, object: CanonicalSemanticFrame.Object?) -> ClockMatch? {
        let colon = #"(?<!\d)([01]?\d|2[0-3]):([0-5]\d)\b"#
        if let match = firstMatch(colon, in: text),
           let hour = integerCapture(1, match, text),
           let minute = integerCapture(2, match, text) {
            return .init(hour: hour, minute: minute, confidence: 0.99, evidence: "explicit_clock", ambiguous: false)
        }

        // A separated hour/minute pair is accepted only in an alarm frame and
        // only after a temporal preposition. This avoids treating arbitrary
        // quantities as a clock.
        if object == .alarm {
            let pair = #"\b(?:о|об|на|at)\s+([01]?\d|2[0-3])\s+([0-5]\d)\b"#
            if let match = firstMatch(pair, in: text),
               let hour = integerCapture(1, match, text),
               let minute = integerCapture(2, match, text) {
                return .init(hour: hour, minute: minute, confidence: 0.94, evidence: "scoped_clock_pair", ambiguous: false)
            }
        }

        let hourOnly = #"\b(?:о|об|at)\s+([01]?\d|2[0-3])\b"#
        if let match = firstMatch(hourOnly, in: text), let hour = integerCapture(1, match, text) {
            return .init(hour: hour, minute: 0, confidence: 0.93, evidence: "scoped_hour", ambiguous: false)
        }
        return nil
    }

    private func dayPeriod(in text: String) -> String? {
        if ["після обіду", "по обіді", "пополудні", "после обеда", "afternoon"].contains(where: text.contains) { return "afternoon" }
        if ["увечері", "вечором", "вечером", "evening", "tonight"].contains(where: text.contains) { return "evening" }
        if ["вранці", "зранку", "утром", "morning"].contains(where: text.contains) { return "morning" }
        return nil
    }

    private func containsWordOrPhrase(_ phrase: String, in text: String) -> Bool {
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let phraseWords = phrase.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard !phraseWords.isEmpty, phraseWords.count <= words.count else { return false }
        return (0...(words.count - phraseWords.count)).contains { start in
            Array(words[start..<(start + phraseWords.count)]) == phraseWords
        }
    }

    private func firstMatch(_ pattern: String, in text: String) -> NSTextCheckingResult? {
        let key = pattern as NSString
        let regex: NSRegularExpression
        if let cached = Self.regexCache.object(forKey: key) {
            regex = cached
        } else {
            guard let compiled = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
            Self.regexCache.setObject(compiled, forKey: key)
            regex = compiled
        }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private func capture(_ index: Int, from match: NSTextCheckingResult, in text: String) -> String? {
        guard match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: text) else { return nil }
        return String(text[range])
    }

    private func integerCapture(_ index: Int, _ match: NSTextCheckingResult, _ text: String) -> Int? {
        capture(index, from: match, in: text).flatMap(Int.init)
    }
}
