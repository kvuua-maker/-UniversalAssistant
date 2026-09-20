import Foundation

struct CanonicalMessageRoles: Equatable, Sendable {
    let recipient: String?
    let body: String?
}

struct CanonicalContactAwareMessageRoles: Equatable, Sendable {
    let recipient: String?
    let body: String?
    let ambiguousRecipients: [String]
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

    static func analyze(_ original: String, explicitService: String? = nil) -> CanonicalMessageRoles? {
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
            let prefix = Array(tail[..<serviceIndex])
            let suffix = Array(tail.dropFirst(serviceIndex + 1))
            // A trailing channel declaration belongs to SERVICE/CHANNEL and
            // terminates recipient extraction. A leading declaration leaves
            // the following recipient/body available to the same role grammar.
            tail = prefix.isEmpty ? suffix : prefix
        }
        removeExplicitService(from: &tail, service: explicitService)
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

    /// Completes only RECIPIENT/BODY inside an already-classified message.
    /// Candidate identities come exclusively from the locally authorized
    /// Contacts vocabulary; weak fuzzy body words are never promoted to people.
    static func analyzeContactAware(
        _ original: String,
        explicitService: String? = nil,
        contactVocabulary: [String]
    ) -> CanonicalContactAwareMessageRoles? {
        let base = analyze(original, explicitService: explicitService)
        let contacts = deduplicated(contactVocabulary)
        guard !contacts.isEmpty else {
            return base.map { .init(recipient: $0.recipient, body: $0.body, ambiguousRecipients: []) }
        }
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
        removeExplicitService(from: &tail, service: explicitService)
        trimLeadingFillers(&tail)
        let candidates = contacts.map {
            ScopedEntityCandidate(value: $0, displayName: $0, aliases: [$0])
        }
        let resolver = ContextScopedEntityResolver(candidates: candidates)
        var matches: [(range: Range<Int>, identity: String, surface: String)] = []
        for start in tail.indices where !isControlToken(tail[start]) {
            for length in 1...min(3, tail.count - start) {
                let range = start..<(start + length)
                let span = Array(tail[range])
                guard !span.contains(where: isControlToken) else { continue }
                let surface = span.map(\.surface).joined(separator: " ")
                let evidence = resolver.resolveWithEvidence(surface)
                guard evidence.bestScore >= 0.96,
                      [.exact, .morphology].contains(evidence.mechanism),
                      case let .resolved(identity) = evidence.resolution else { continue }
                matches.append((range, identity, surface))
            }
        }
        guard !matches.isEmpty else {
            return base.map { .init(recipient: $0.recipient, body: $0.body, ambiguousRecipients: []) }
        }
        let longest = matches.map { $0.range.count }.max() ?? 1
        let strongest = matches.filter { $0.range.count == longest }
        let identities = deduplicated(strongest.map(\.identity))
        guard identities.count == 1, let selected = strongest.first else {
            return .init(recipient: nil, body: base?.body, ambiguousRecipients: identities)
        }

        let body: String?
        if let colonBody, !colonBody.isEmpty {
            body = colonBody
        } else {
            let remaining = tail.enumerated().compactMap { index, token -> Token? in
                guard !selected.range.contains(index), !isBodyControlToken(token) else { return nil }
                return token
            }
            let value = remaining.map(\.surface).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            body = value.isEmpty ? nil : value
        }
        return .init(recipient: selected.surface, body: body, ambiguousRecipients: [])
    }

    private static func tokenize(_ value: String) -> [Token] {
        value.split { character in
            !character.isLetter && !character.isNumber && character != "'" && character != "’"
        }.map { slice in
            let surface = String(slice)
            let normalized = CanonicalMorphology.comparableText(surface)
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
            "відкр", "откр", "покаж", "open", "show",
            "message", "send", "text", "write"
        ])
    }

    private static func isMessageObject(_ token: Token) -> Bool {
        matches(token, roots: ["повідомлен", "сообщен", "message", "sms", "текст", "чат", "переписк", "розмов", "conversation", "thread"])
    }

    private static func isServiceBoundary(_ token: Token) -> Bool {
        ["через", "via", "using", "каналом", "канал"].contains(token.normalized)
    }

    private static func isContentBoundary(_ token: Token) -> Bool {
        ["що", "что", "that", "про", "щодо", "about"].contains(token.normalized)
    }

    private static func isControlToken(_ token: Token) -> Bool {
        isMessageObject(token) || isServiceBoundary(token) || isContentBoundary(token) ||
            ["u", "v", "у", "в", "по", "to", "for", "для", "до"].contains(token.normalized) ||
            serviceCandidates.contains { candidate in
                candidate.aliases.union([candidate.displayName]).contains {
                    CanonicalMorphology.comparableText($0) == token.normalized
                }
            }
    }

    private static func isBodyControlToken(_ token: Token) -> Bool {
        isMessageObject(token) || isServiceBoundary(token) || isContentBoundary(token) ||
            ["у", "в", "по", "via", "using", "канал", "каналом"].contains(token.normalized) ||
            serviceCandidates.contains { candidate in
                candidate.aliases.union([candidate.displayName]).contains {
                    CanonicalMorphology.comparableText($0) == token.normalized
                }
            }
    }

    private static func deduplicated(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert(CanonicalMorphology.comparableText($0)).inserted }
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
        while tokens.first.map({ ["для", "до", "з", "із", "зі", "с", "to", "for"].contains($0.normalized) }) == true {
            tokens.removeFirst()
        }
    }

    private static func removeExplicitService(from tokens: inout [Token], service: String?) {
        let serviceKind = service.flatMap(normalizedService)
        if serviceKind == "email" {
            tokens.removeAll(where: isEmailServiceToken)
            while tokens.last.map({ ["через", "via", "using", "у", "в", "по", "канал", "каналом"].contains($0.normalized) }) == true {
                tokens.removeLast()
            }
            return
        }
        guard let serviceKind else { return }
        let resolver = ContextScopedEntityResolver(candidates: serviceCandidates)
        guard let index = tokens.firstIndex(where: { token in
            guard case let .resolved(value) = resolver.resolve(token.surface) else { return false }
            return value == serviceKind
        }) else { return }
        tokens.remove(at: index)
        if index > 0, tokens.indices.contains(index - 1),
           ["через", "via", "using", "у", "в", "по", "канал", "каналом"].contains(tokens[index - 1].normalized) {
            tokens.remove(at: index - 1)
        }
    }

    private static func normalizedService(_ value: String) -> String? {
        switch value.lowercased() {
        case "messages", "whatsapp", "telegram", "viber", "signal", "email": value.lowercased()
        case "mail": "email"
        default: nil
        }
    }

    private static let serviceCandidates: [ScopedEntityCandidate<String>] =
        MessengerKind.allCases.map { kind in
            .init(
                value: kind.rawValue,
                displayName: kind.rawValue,
                aliases: CanonicalSpeechEntityRegistry.communicationAliases[kind.rawValue] ?? [kind.rawValue]
            )
        } + [
            .init(value: "email", displayName: "email", aliases: ["email", "mail", "пошта", "почта"])
        ]


    private static func isEmailServiceToken(_ token: Token) -> Bool {
        token.morphology.contains { form in
            ["email", "mail", "пошт", "почт", "електрон", "электрон", "лист"].contains {
                form.hasPrefix($0)
            }
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
