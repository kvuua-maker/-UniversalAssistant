import Foundation

enum LocalUtilityError: Error, Equatable { case unsupported, invalidNumber, divisionByZero }

struct LocalUtilityEngine: Sendable {
    static func recognizes(_ raw: String) -> Bool {
        let text = normalized(raw)
        let signals = ["обчисл", "порах", "розрах", "вычисл", "посчитай", "calculate", "різниц", "разниц", "difference", "сума", "сумм", "sum", "добут", "произвед", "product", "частк", "частн", "quotient", "скільки буде", "сколько будет", "помнож", "умнож", "поділ", "раздел", "kilometer", "кілометр", "километр", "miles", "мил", "кілограм", "килограмм", "pounds", "фунт", "celsius", "fahrenheit", "цельсі", "цельси", "який сьогодні день", "какой сегодня день", "яка сьогодні дата", "какая сегодня дата", "яке сьогодні число", "какое сегодня число", "котра година", "который час", "скільки зараз часу", "сколько сейчас времени", "який зараз час", "local time"]
        let currentDate = ["дат", "числ", "date"].contains(where: text.contains) && ["сьогод", "сегодня", "поточ", "текущ", "current", "today"].contains(where: text.contains)
        let currentTime = ["час", "годин", "врем", "time"].contains(where: text.contains) && ["зараз", "сейчас", "поточ", "текущ", "місцев", "местн", "current", "local"].contains(where: text.contains)
        let range = NSRange(text.startIndex..., in: text)
        let numericExpression = numericExpressionRegex.firstMatch(in: text, range: range) != nil
        let percentageExpression = percentageExpressionRegex.firstMatch(in: text, range: range) != nil
        return signals.contains(where: text.contains) || currentDate || currentTime || numericExpression || percentageExpression
    }

    static func recognizesCurrency(_ raw: String) -> Bool {
        let text = normalized(raw)
        let currency = ["долар", "доллар", "гривн", "євро", "евро", "злот", "фунт", "франк", "крон", "ієн", "иен", "usd", "uah", "eur", "pln", "gbp", "chf", "czk", "jpy", "курс валют"].filter { text.contains($0) }.count
        return currency >= 2 || text.contains("курс долара") || text.contains("курс евро") || text.contains("курс євро")
    }

    func execute(_ raw: String, locale: Locale, timeZone: TimeZone, now: Date) throws -> String {
        let text = Self.normalized(raw)
        if text.contains("день тижня") || text.contains("день недели") || text.contains("day of the week") {
            return format(now, template: "EEEE", locale: locale, timeZone: timeZone)
        }
        if ["дат", "числ", "date"].contains(where: text.contains) && ["сьогод", "сегодня", "поточ", "текущ", "current", "today"].contains(where: text.contains) {
            return format(now, template: "d MMMM y", locale: locale, timeZone: timeZone)
        }
        if text.contains("котра година") || text.contains("который час") || (["час", "годин", "врем", "time"].contains(where: text.contains) && ["зараз", "сейчас", "поточ", "текущ", "місцев", "местн", "current", "local"].contains(where: text.contains)) {
            return format(now, template: "HH:mm", locale: locale, timeZone: timeZone)
        }
        if let value = try percentage(text) { return format(value, locale: locale) }
        if let value = try conversion(text) { return format(value.value, locale: locale) + " " + value.unit }
        if let value = try arithmetic(text) { return format(value, locale: locale) }
        throw LocalUtilityError.unsupported
    }

    private func arithmetic(_ text: String) throws -> Double? {
        if let value = try relationalArithmetic(text) { return value }
        if let value = try chainedArithmetic(text) { return value }
        let operators: [(String, (Double, Double) throws -> Double)] = [
            (#"(?:(?:помножити|помнож|умножить|умножь)(?:\s+на)?|times|multiplied by|×|\*)"#, { $0 * $1 }),
            (#"(?:поділити на|подели на|разделить на|divided by|÷|/)"#, { guard $1 != 0 else { throw LocalUtilityError.divisionByZero }; return $0 / $1 }),
            (#"(?:додати|додай|сложить|прибавить|плюс|plus|\+)"#, { $0 + $1 }),
            (#"(?:відняти|відніми|вычесть|отнять|мінус|минус|minus|-)"#, { $0 - $1 })
        ]
        for (token, operation) in operators {
            let pattern = "(" + Self.numberPattern + ")\\s*" + token + "\\s*(" + Self.numberPattern + ")"
            if let values = captures(pattern, text), values.count == 2 { return try operation(values[0], values[1]) }
        }
        return nil
    }

    private func relationalArithmetic(_ text: String) throws -> Double? {
        let between = #"[^0-9+\-]*("# + Self.numberPattern + #")[^0-9+\-]+(?:і|и|and|та)\s*("# + Self.numberPattern + ")"
        if let values = captures(#"(?:різниц\p{L}*|разниц\p{L}*|difference)\s+(?:між|между|between)"# + between, text), values.count == 2 {
            return values[0] - values[1]
        }
        if let values = captures(#"(?:сум\p{L}*|sum)\s*(?:між|между|between|чисел)?"# + between, text), values.count == 2 {
            return values[0] + values[1]
        }
        if let values = captures(#"(?:добут\p{L}*|произвед\p{L}*|product)\s*(?:між|между|between|чисел)?"# + between, text), values.count == 2 {
            return values[0] * values[1]
        }
        if let values = captures(#"(?:частк\p{L}*|частн\p{L}*|quotient)\s*(?:між|между|between|чисел)?"# + between, text), values.count == 2 {
            guard values[1] != 0 else { throw LocalUtilityError.divisionByZero }
            return values[0] / values[1]
        }
        return nil
    }

    private func chainedArithmetic(_ text: String) throws -> Double? {
        let operatorPattern = #"(?:помножити|помнож|умножить|умножь)(?:\s+на)?|times|multiplied by|×|\*|поділити на|подели на|разделить на|divided by|÷|/|додати|додай|сложить|прибавить|плюс|plus|\+|відняти|відніми|вычесть|отнять|мінус|минус|minus|-"#
        let pattern = "(" + Self.numberPattern + ")|(" + operatorPattern + ")"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var numbers: [Double] = []; var operations: [String] = []
        for match in matches {
            if match.range(at: 1).location != NSNotFound, let range = Range(match.range(at: 1), in: text), let value = Double(text[range].replacingOccurrences(of: ",", with: ".")) { numbers.append(value) }
            else if match.range(at: 2).location != NSNotFound, let range = Range(match.range(at: 2), in: text) { operations.append(String(text[range]).lowercased()) }
        }
        guard numbers.count >= 2, operations.count == numbers.count - 1 else { return nil }
        var result = numbers[0]
        for index in operations.indices {
            let op = operations[index], rhs = numbers[index + 1]
            if op.contains("помнож") || op.contains("умнож") || op.contains("times") || op.contains("multiplied") || op == "×" || op == "*" { result *= rhs }
            else if op.contains("поділ") || op.contains("подел") || op.contains("раздел") || op.contains("divided") || op == "÷" || op == "/" { guard rhs != 0 else { throw LocalUtilityError.divisionByZero }; result /= rhs }
            else if op.contains("дод") || op.contains("слож") || op.contains("прибав") || op.contains("плюс") || op.contains("plus") || op == "+" { result += rhs }
            else { result -= rhs }
        }
        return result
    }

    private func percentage(_ text: String) throws -> Double? {
        let ofPattern = "(" + Self.numberPattern + #")\s*(?:%|відсот(?:ок|ки|ків)?|процент(?:а|ов)?)\s*(?:від|от|of)\s*("# + Self.numberPattern + ")"
        if let values = captures(ofPattern, text), values.count == 2 { return values[1] * values[0] / 100 }
        let changePattern = #"(?:збільш|увелич|increase|зменш|уменьш|decrease)[^0-9+\-]*("# + Self.numberPattern + #")[^0-9+\-]+(?:на|by)\s*("# + Self.numberPattern + #")\s*(?:%|відсот|процент)"#
        if let values = captures(changePattern, text), values.count == 2 {
            let decrease = ["зменш", "уменьш", "decrease"].contains(where: text.contains)
            return values[0] * (1 + (decrease ? -1 : 1) * values[1] / 100)
        }
        return nil
    }

    private func conversion(_ text: String) throws -> (value: Double, unit: String)? {
        guard let value = captures("(" + Self.numberPattern + ")", text)?.first else { return nil }
        let pairs: [(from: [String], to: [String], factor: Double, unit: String)] = [
            (["кілометр", "километр", "kilometer", "km"], ["мил", "mile"], 0.6213711922, "mi"),
            (["кілометр", "километр", "kilometer", "km"], ["метр", "meter", "m"], 1000, "m"),
            (["метр", "meter"], ["кілометр", "километр", "kilometer", "km"], 0.001, "km"),
            (["мил", "mile"], ["кілометр", "километр", "kilometer", "km"], 1.609344, "km"),
            (["кілограм", "килограмм", "kilogram", "kg"], ["фунт", "pound", "lb"], 2.2046226218, "lb"),
            (["фунт", "pound", "lb"], ["кілограм", "килограмм", "kilogram", "kg"], 0.45359237, "kg"),
            (["метр", "meter"], ["фут", "feet", "foot"], 3.280839895, "ft"),
            (["літр", "литр", "liter"], ["галон", "gallon"], 0.2641720524, "US gal")
        ]
        for pair in pairs where containsOrdered(text, pair.from, pair.to) { return (value * pair.factor, pair.unit) }
        if containsOrdered(text, ["цельсі", "цельси", "celsius"], ["фаренгейт", "fahrenheit"]) { return (value * 9 / 5 + 32, "°F") }
        if containsOrdered(text, ["фаренгейт", "fahrenheit"], ["цельсі", "цельси", "celsius"]) { return ((value - 32) * 5 / 9, "°C") }
        return nil
    }

    private func containsOrdered(_ text: String, _ from: [String], _ to: [String]) -> Bool {
        guard let a = from.compactMap({ text.range(of: $0)?.lowerBound }).min(), let b = to.compactMap({ text.range(of: $0)?.lowerBound }).min() else { return false }
        return a < b
    }

    private func captures(_ pattern: String, _ text: String) -> [Double]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).compactMap { index -> Double? in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return Double(text[range].replacingOccurrences(of: ",", with: "."))
        }
    }

    private func format(_ value: Double, locale: Locale) -> String {
        value.formatted(.number.precision(.fractionLength(0...6)).locale(locale))
    }

    private func format(_ date: Date, template: String, locale: Locale, timeZone: TimeZone) -> String {
        let formatter = DateFormatter(); formatter.locale = locale; formatter.timeZone = timeZone; formatter.setLocalizedDateFormatFromTemplate(template); return formatter.string(from: date)
    }

    private static let numberPattern = #"[-+]?\d+(?:[.,]\d+)?"#
    private static let numericExpressionRegex = try! NSRegularExpression(pattern: #"[-+]?\d+(?:[.,]\d+)?\s*[+×*\/÷-]\s*[-+]?\d+(?:[.,]\d+)?"#)
    private static let percentageExpressionRegex = try! NSRegularExpression(pattern: #"[-+]?\d+(?:[.,]\d+)?[^\d]{0,20}(?:%|відсот|процент)"#, options: [.caseInsensitive])
    private static func normalized(_ raw: String) -> String {
        var value = raw.lowercased()
        for apostrophe in ["’", "ʼ", "‘", "`", "\u{02BB}"] {
            value = value.replacingOccurrences(of: apostrophe, with: "\u{27}")
        }
        let compact = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return StructuredNumberNormalizer.normalize(compact)
    }
}
