# M10 Localization and Accessibility QA

Requirements 468–470, 796–800, 835 and 838–839 are traced to executable behavior. All five shipped locales have identical nonempty keys and preserve the required format placeholder. Currency and relative dates now use the active SwiftUI locale, so changing language/region does not mutate stored money or intent state. Tests cover German/French long critical labels and Ukrainian/Russian Cyrillic labels.

The primary microphone control has a semantic start/stop label and a 112-point visual target. Status/result components expose accessibility identifiers or combined semantics, decorative product imagery is hidden, and every critical voice path has the visible typed-command field and submit action. Views use semantic text styles without a fixed Dynamic Type ceiling.

No count-dependent user-facing phrase currently exists, so plural rules are `NOT_APPLICABLE_VERIFIED` for the current UI rather than claimed through placeholder strings. Physical-device spoken/recognized Ukrainian/Russian mixed-language, names, addresses, brands and colloquial pronunciation remain a real-device verification item; local parser tests do not replace it.
