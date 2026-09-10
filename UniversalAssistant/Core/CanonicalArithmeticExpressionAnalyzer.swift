import Foundation

/// Typed arithmetic evidence produced before capability selection.
/// Operator stems are lexical evidence inside this bounded grammar; they do
/// not select an assistant capability on their own.
struct CanonicalArithmeticExpression: Equatable, Sendable {
    enum Operation: String, Equatable, Sendable {
        case add, subtract, multiply, divide
    }

    struct Step: Equatable, Sendable {
        let operation: Operation
        let operand: Double
    }

    let initialValue: Double
    let steps: [Step]
    let confidence: Double
    let evidence: Set<String>

    func evaluate() throws -> Double {
        var value = initialValue
        for step in steps {
            switch step.operation {
            case .add: value += step.operand
            case .subtract: value -= step.operand
            case .multiply: value *= step.operand
            case .divide:
                guard step.operand != 0 else { throw LocalUtilityError.divisionByZero }
                value /= step.operand
            }
        }
        return value
    }
}

enum CanonicalArithmeticExpressionAnalyzer {
    private struct NumberEvidence {
        let range: NSRange
        let value: Double
    }

    private struct OperatorEvidence {
        let range: NSRange
        let operation: CanonicalArithmeticExpression.Operation
        let surface: String
    }

    private static let numberRegex = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\d])[-+]?\d+(?:[.,]\d+)?(?![\p{L}\d])"#
    )
    private static let operatorRegex = try! NSRegularExpression(
        pattern: #"(?:помнож\p{L}*|умнож\p{L}*|multipl\p{L}*|times|поділ\p{L}*|розділ\p{L}*|подел\p{L}*|раздел\p{L}*|divid\p{L}*|дод\p{L}*|склад\p{L}*|слож\p{L}*|прибав\p{L}*|add\p{L}*|плюс|plus|віднім\p{L}*|віднят\p{L}*|выч\p{L}*|отнят\p{L}*|subtract\p{L}*|мінус|минус|minus|[+×*\/÷-])"#,
        options: [.caseInsensitive]
    )
    private static let calendarDateRegex = try! NSRegularExpression(
        pattern: #"(?<!\d)\d{1,2}[./-]\d{1,2}[./-]\d{2,4}(?!\d)"#
    )

    static func analyze(_ raw: String) -> CanonicalArithmeticExpression? {
        let text = StructuredNumberNormalizer.normalize(raw.lowercased())
        let wholeRange = NSRange(text.startIndex..., in: text)
        let lexicalOperators = operators(in: text, range: wholeRange).filter {
            !["/", "-"].contains($0.surface)
        }
        // Date separators are not arithmetic evidence. A verbal operator in
        // the same command is still allowed to establish an expression.
        if calendarDateRegex.firstMatch(in: text, range: wholeRange) != nil,
           lexicalOperators.isEmpty {
            return nil
        }

        let numbers = numberRegex.matches(in: text, range: wholeRange).compactMap { match -> NumberEvidence? in
            guard let range = Range(match.range, in: text),
                  let value = Double(text[range].replacingOccurrences(of: ",", with: ".")) else { return nil }
            return .init(range: match.range, value: value)
        }
        let operators = operators(in: text, range: wholeRange)
        guard numbers.count >= 2, !operators.isEmpty else { return nil }

        var steps: [CanonicalArithmeticExpression.Step] = []
        var initial = numbers[0].value
        var evidence: Set<String> = []

        for index in 0..<(numbers.count - 1) {
            let left = numbers[index]
            let right = numbers[index + 1]
            let betweenStart = NSMaxRange(left.range)
            let betweenEnd = right.range.location
            let between = NSRange(location: betweenStart, length: max(0, betweenEnd - betweenStart))
            let betweenOperators = operators.filter { NSIntersectionRange($0.range, between).length > 0 }
            let selected: OperatorEvidence?
            var selectedFromPrefix = false
            if let nearestBetween = betweenOperators.last {
                selected = nearestBetween
            } else if index == 0 {
                selected = operators
                    .filter { NSMaxRange($0.range) <= left.range.location }
                    .last
                selectedFromPrefix = selected != nil
            } else {
                selected = nil
            }
            guard let selected else { return nil }
            if selectedFromPrefix,
               !containsPrefixOperandConnector(text, between: between, operation: selected.operation) {
                return nil
            }
            evidence.insert("operator:\(selected.operation.rawValue)")

            if index == 0,
               selected.operation == .subtract,
               selected.range.location < left.range.location,
               containsReverseSubtractionMarker(text, between: between) {
                initial = right.value
                steps.append(.init(operation: .subtract, operand: left.value))
            } else {
                steps.append(.init(operation: selected.operation, operand: right.value))
            }
        }

        guard steps.count == numbers.count - 1 else { return nil }
        if text.contains("результат") || text.contains("підсумок") ||
            text.contains("итог") || text.contains("result") {
            evidence.insert("typed_result_continuation")
        }
        return .init(
            initialValue: initial,
            steps: steps,
            confidence: steps.count > 1 ? 0.98 : 0.96,
            evidence: evidence
        )
    }

    private static func operators(in text: String, range: NSRange) -> [OperatorEvidence] {
        operatorRegex.matches(in: text, range: range).compactMap { match in
            guard let valueRange = Range(match.range, in: text) else { return nil }
            let surface = String(text[valueRange]).lowercased()
            let operation: CanonicalArithmeticExpression.Operation
            if surface == "+" || surface.hasPrefix("дод") || surface.hasPrefix("склад") ||
                surface.hasPrefix("слож") || surface.hasPrefix("прибав") || surface.hasPrefix("add") ||
                surface == "плюс" || surface == "plus" {
                operation = .add
            } else if surface == "-" || surface.hasPrefix("віднім") || surface.hasPrefix("віднят") ||
                surface.hasPrefix("выч") || surface.hasPrefix("отнят") || surface.hasPrefix("subtract") ||
                surface == "мінус" || surface == "минус" || surface == "minus" {
                operation = .subtract
            } else if surface == "×" || surface == "*" || surface.hasPrefix("помнож") ||
                surface.hasPrefix("умнож") || surface.hasPrefix("multipl") || surface == "times" {
                operation = .multiply
            } else {
                operation = .divide
            }
            return .init(range: match.range, operation: operation, surface: surface)
        }
    }

    private static func containsReverseSubtractionMarker(_ text: String, between range: NSRange) -> Bool {
        guard let swiftRange = Range(range, in: text) else { return false }
        let words = text[swiftRange].split(whereSeparator: { !$0.isLetter }).map(String.init)
        return words.contains(where: { ["від", "из", "from"].contains($0) })
    }

    private static func containsPrefixOperandConnector(
        _ text: String,
        between range: NSRange,
        operation: CanonicalArithmeticExpression.Operation
    ) -> Bool {
        guard let swiftRange = Range(range, in: text) else { return false }
        let words = text[swiftRange].split(whereSeparator: { !$0.isLetter }).map(String.init)
        let accepted: Set<String> = switch operation {
        case .multiply, .divide: ["на", "by"]
        case .subtract: ["від", "из", "from"]
        case .add: ["до", "к", "to", "and", "і", "та", "и"]
        }
        return !accepted.isDisjoint(with: words)
    }
}
