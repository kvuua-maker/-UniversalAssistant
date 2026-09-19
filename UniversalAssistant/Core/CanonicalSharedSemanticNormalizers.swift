import Foundation

enum CanonicalLocalityNormalizer {
    private static let canonical: [String] = [
        "Київ", "Львів", "Одеса", "Харків", "Дніпро", "Запоріжжя",
        "Полтава", "Черкаси", "Чернівці", "Івано-Франківськ", "Тернопіль",
        "Луцьк", "Рівне", "Житомир", "Вінниця", "Хмельницький",
        "Ужгород", "Миколаїв", "Херсон", "Чернігів", "Суми", "Кропивницький"
    ]

    static func normalize(_ value: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .replacingOccurrences(of: #"^(?:у|в|in|at)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
        guard !cleaned.isEmpty else { return value }
        let evidence = CanonicalMorphology.forms(for: cleaned)
        if let match = canonical.first(where: { city in
            let cityForms = CanonicalMorphology.forms(for: city)
            return !evidence.isDisjoint(with: cityForms) ||
                evidence.contains(CanonicalMorphology.comparableText(city)) ||
                isCloseInflectedForm(cleaned, canonical: city)
        }) { return match }
        return cleaned
    }

    /// Handles stem alternations produced by Ukrainian case inflection (for
    /// example Київ → Києві) without maintaining provider-specific city lists.
    /// A close match is accepted only when the shared prefix is substantial
    /// and the bounded edit distance is small across the complete locality.
    private static func isCloseInflectedForm(_ value: String, canonical: String) -> Bool {
        let lhs = Array(CanonicalMorphology.comparableText(value))
        let rhs = Array(CanonicalMorphology.comparableText(canonical))
        guard min(lhs.count, rhs.count) >= 4 else { return false }
        let commonPrefix = zip(lhs, rhs).prefix(while: { $0 == $1 }).count
        guard commonPrefix >= 2 else { return false }
        var previous = Array(0...rhs.count)
        for (row, left) in lhs.enumerated() {
            var current = [row + 1]
            for (column, right) in rhs.enumerated() {
                current.append(min(
                    current[column] + 1,
                    previous[column + 1] + 1,
                    previous[column] + (left == right ? 0 : 1)
                ))
            }
            previous = current
        }
        return previous[rhs.count] <= 2
    }
}

enum CanonicalProductQueryBuilder {
    static func query(for command: StructuredCommand, selectedProviderOrBrand: String? = nil) -> String {
        let raw = command.entities["product"] ?? command.entities["query"] ?? command.originalText
        let excludedRoots = [
            "куп", "знайд", "покаж", "відк", "замов", "потріб", "хоч", "придб",
            "buy", "find", "show", "open", "order", "want", "please"
        ]
        let selectedTokens = Set((selectedProviderOrBrand ?? "")
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { CanonicalMorphology.comparableText(String($0)) })
        var tokens = raw.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        tokens.removeAll { token in
            let comparable = CanonicalMorphology.comparableText(token)
            return excludedRoots.contains(where: comparable.hasPrefix) || selectedTokens.contains(comparable)
        }
        if let brand = command.constraints.brand ?? command.entities["brand"] {
            let brandTokens = Set(brand.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map { CanonicalMorphology.comparableText(String($0)) })
            tokens.removeAll { brandTokens.contains(CanonicalMorphology.comparableText($0)) }
        }
        let result = tokens.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? raw.trimmingCharacters(in: .whitespacesAndNewlines) : result
    }
}
