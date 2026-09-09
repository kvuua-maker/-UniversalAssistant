import Foundation

struct CanonicalMessageRoles: Equatable, Sendable {
    let recipient: String?
    let body: String?
}

/// Extracts message participants and content after the command has been
/// structurally classified as communication. It is deliberately a role grammar:
/// person names, services and message contents are data, never phrase aliases.
enum CanonicalMessageRoleAnalyzer {
    private struct Token {
        let surface: String
        let normalized: String
        let morphology: Set<String>
    }

    static func analyze(_ original: String) -> CanonicalMessageRoles? {
        let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let colon = trimmed.firstIndex(where: { $0 == ":" || $0 == "：" })
        let commandSurface = colon.map { String(trimmed[..<$0]) } ?? trimmed
        let colonBody = colon.map {
            String(trimmed[trimmed.index(after: $0)...])
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        }

        let tokens = tokenize(commandSurface)
        guard let actionIndex = tokens.firstIndex(where: isMessageAction) else { return nil }
        var tail = Array(tokens.dropFirst(actionIndex + 1))
        guard !tail.isEmpty || !(colonBody ?? "").isEmpty else {
            return .init(recipient: nil, body: nil)
        }

        if let serviceIndex = tail.firstIndex(where: isServiceBoundary) {
            tail = Array(tail[..<serviceIndex])
        }
        trimLeadingFillers(&tail)

        if let colonBody, !colonBody.isEmpty {
            let recipient = recipientText(removingLeadingMessageObject(from: tail))
            return .init(recipient: recipient, body: colonBody)
        }

        if let objectIndex = tail.firstIndex(where: isMessageObject) {
            if objectIndex == 0 {
                tail.removeFirst()
                trimLeadingRecipientMarker(&tail)
                if let boundary = tail.firstIndex(where: isContentBoundary) {
                    return .init(
                        recipient: recipientText(Array(tail[..<boundary])),
                        body: contentText(from: tail, boundary: boundary)
                    )
                }
                return .init(recipient: recipientText(tail), body: nil)
            }

            let recipient = recipientText(Array(tail[..<objectIndex]))
            let bodyTokens = Array(tail.dropFirst(objectIndex + 1))
            return .init(
                recipient: recipient,
                body: bodyTokens.isEmpty ? nil : bodyTokens.map(\.surface).joined(separator: " ")
            )
        }

        if let boundary = tail.firstIndex(where: isContentBoundary) {
            return .init(
                recipient: recipientText(Array(tail[..<boundary])),
                body: contentText(from: tail, boundary: boundary)
            )
        }
        return .init(recipient: recipientText(tail), body: nil)
    }

    private static func tokenize(_ value: String) -> [Token] {
        value.split { character in
            !character.isLetter && !character.isNumber && character != "'" && character != "’"
        }.map { slice in
            let surface = String(slice)
            let normalized = surface.precomposedStringWithCompatibilityMapping
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "uk_UA"))
                .lowercased()
            return .init(
                surface: surface,
                normalized: normalized,
                morphology: CanonicalMorphology.forms(for: normalized)
            )
        }
    }

    private static func isMessageAction(_ token: Token) -> Bool {
        matches(token, roots: [
            "напиш", "надішл", "відправ", "повідом", "отправ", "сообщ",
            "message", "send", "text", "write"
        ])
    }

    private static func isMessageObject(_ token: Token) -> Bool {
        matches(token, roots: ["повідомлен", "сообщен", "message", "sms", "текст"])
    }

    private static func isServiceBoundary(_ token: Token) -> Bool {
        ["через", "via", "using", "каналом", "канал"].contains(token.normalized)
    }

    private static func isContentBoundary(_ token: Token) -> Bool {
        ["що", "что", "that", "про", "щодо", "about"].contains(token.normalized)
    }

    private static func contentText(from tokens: [Token], boundary: Int) -> String? {
        let includeBoundary = ["про", "щодо", "about"].contains(tokens[boundary].normalized)
        let start = includeBoundary ? boundary : boundary + 1
        guard start < tokens.count else { return nil }
        let value = tokens[start...].map(\.surface).joined(separator: " ")
        return value.isEmpty ? nil : value
    }

    private static func removingLeadingMessageObject(from tokens: [Token]) -> [Token] {
        guard tokens.first.map(isMessageObject) == true else { return tokens }
        var value = Array(tokens.dropFirst())
        trimLeadingRecipientMarker(&value)
        return value
    }

    private static func trimLeadingFillers(_ tokens: inout [Token]) {
        while tokens.first.map({ ["будь", "ласка", "please"].contains($0.normalized) }) == true {
            tokens.removeFirst()
        }
    }

    private static func trimLeadingRecipientMarker(_ tokens: inout [Token]) {
        while tokens.first.map({ ["для", "to", "for"].contains($0.normalized) }) == true {
            tokens.removeFirst()
        }
    }

    private static func recipientText(_ tokens: [Token]) -> String? {
        var value = tokens
        trimLeadingRecipientMarker(&value)
        let text = value.map(\.surface).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return text.isEmpty ? nil : text
    }

    private static func matches(_ token: Token, roots: [String]) -> Bool {
        token.morphology.contains { form in roots.contains { form.hasPrefix($0) } }
    }
}

