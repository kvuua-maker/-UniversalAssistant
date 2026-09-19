import Foundation

/// Produces reusable inflection evidence for structural role analysis.
///
/// NaturalLanguage exposes tokenization/language evidence for Ukrainian and
/// Russian on the deployment SDK, but does not expose the Lemma tag scheme for
/// either language. These productive suffix rules therefore emit *candidate
/// forms*, never an asserted dictionary lemma. Capability selection still needs
/// a compatible action/object/source role combination.
enum CanonicalMorphology {
    /// Canonical comparison form shared by semantic-role and entity helpers.
    /// Latin diacritics are comparison noise, while Cyrillic diacritics can be
    /// distinct letters (for example Ukrainian й), so they must be preserved.
    static func comparableText(_ rawValue: String) -> String {
        let lowered = rawValue.precomposedStringWithCompatibilityMapping
            .lowercased(with: Locale(identifier: "uk_UA"))
        let containsCyrillic = lowered.unicodeScalars.contains { cyrillic.contains($0) }
        let normalized = containsCyrillic ? lowered : lowered.folding(
            options: .diacriticInsensitive,
            locale: Locale(identifier: "en_US_POSIX")
        )
        return normalized.filter { $0.isLetter || $0.isNumber }
    }

    static func forms(for rawToken: String) -> Set<String> {
        let lowered = rawToken.precomposedStringWithCompatibilityMapping
            .lowercased(with: Locale(identifier: "uk_UA"))
        // Diacritic folding is a Latin-name comparison aid. On Cyrillic it
        // changes real letters (Ukrainian й → и), so morphology would emit
        // evidence for a different word and could corrupt structural roles.
        let containsCyrillic = lowered.unicodeScalars.contains { cyrillic.contains($0) }
        let normalized = containsCyrillic ? lowered : lowered.folding(
            options: .diacriticInsensitive,
            locale: Locale(identifier: "en_US_POSIX")
        )
        let token = normalized
            .filter { $0.isLetter || $0.isNumber }
        guard !token.isEmpty else { return [] }

        var forms: Set<String> = [token]
        if token.unicodeScalars.contains(where: { Self.cyrillic.contains($0) }) {
            addProductiveForms(of: token, suffixes: nominalSuffixes, into: &forms)
            addProductiveForms(of: token, suffixes: verbalSuffixes, into: &forms)
            // A case suffix can follow an adjective/participle suffix. One
            // bounded second pass captures this without recursively reducing
            // an arbitrary word to a guessed root.
            for form in Array(forms) where form != token {
                addProductiveForms(of: form, suffixes: nominalSuffixes, into: &forms)
            }
        } else {
            addProductiveForms(of: token, suffixes: latinSuffixes, into: &forms)
        }
        return forms
    }

    static func representative(for rawToken: String) -> String {
        let forms = forms(for: rawToken)
        return forms.min { lhs, rhs in
            lhs.count == rhs.count ? lhs < rhs : lhs.count < rhs.count
        } ?? rawToken
    }

    private static func addProductiveForms(
        of token: String,
        suffixes: [String],
        into forms: inout Set<String>
    ) {
        for suffix in suffixes where token.hasSuffix(suffix) {
            let candidate = String(token.dropLast(suffix.count))
            if candidate.count >= 3 { forms.insert(candidate) }
        }
    }

    private static let cyrillic = CharacterSet(charactersIn: "АБВГҐДЕЄЖЗИІЇЙКЛМНОПРСТУФХЦЧШЩЬЮЯЫЭЪЁабвгґдеєжзиіїйклмнопрстуфхцчшщьюяыэъё")

    // Productive case/adjective endings shared by Ukrainian/Russian command
    // entities. They are linguistic classes; no person, city or phrase appears.
    private static let nominalSuffixes = [
        "ього", "його", "иями", "ями", "ами", "ові", "єві", "еві", "ого", "ому", "ему",
        "ими", "іми", "его", "ою", "ею", "ию", "ью", "ах", "ях", "ам", "ям", "ів", "їв",
        "ов", "ев", "ей", "ом", "ем", "ою", "ій", "ой", "у", "ю", "і", "и", "а", "я", "е", "о", "ь"
    ]

    // Imperative, infinitive and common finite endings. Prefix handling remains
    // in the action-role analyzer, so this does not manufacture an action.
    private static let verbalSuffixes = [
        "уватимуть", "юватимуть", "атимуть", "итимуть", "увати", "ювати", "атися", "итися",
        "аються", "уються", "иться", "еться", "ются", "ати", "яти", "ити", "їти", "єте", "ете",
        "ите", "уть", "ють", "ять", "ать", "єш", "еш", "иш", "ала", "яла", "ила", "али", "яли",
        "или", "ай", "яй", "уй", "іть", "йте", "є", "ет", "ит"
    ]

    private static let latinSuffixes = ["ingly", "ation", "ments", "ment", "ing", "ied", "ies", "ed", "es", "s"]
}
