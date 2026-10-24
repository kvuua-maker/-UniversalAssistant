import Foundation

/// One production registry for spoken application and communication names.
/// Aliases are accepted only when they occur in current ASR evidence; they are
/// never unconditional transcript replacements.
enum CanonicalSpeechEntityRegistry {
    static let applicationAliases: [String: Set<String>] = [
        "whatsapp": ["whatsapp", "whats", "wats", "ватсап", "вотсап", "ватс", "вац"],
        "viber": ["viber", "вайбер", "вібер"],
        "telegram": ["telegram", "телеграм", "телега"],
        "spotify": ["spotify", "спотіфай", "спотифай"],
        "youtube": ["youtube", "ютуб"],
        "apple-music": ["apple music", "епл мюзік", "эппл мьюзик"],
        "files": ["files", "файли", "файлы"],
        "camera": ["camera", "камера", "камеру"],
        "calendar": ["calendar", "календар", "календарь"],
        "photos": ["photos", "photo", "фото", "фотографії", "фотографии"],
        "settings": ["settings", "налаштування", "настройки"],
        "contacts": ["contacts", "контакти", "контакты"],
        "reminders": ["reminders", "нагадування", "напоминания"],
        "clock": ["clock", "годинник", "часы"],
        "safari": ["safari", "сафарі"],
        "maps": ["maps", "apple maps", "мапи", "карти"],
        "voice-memos": ["voice memos", "диктофон", "голосові записи"],
        "mail": ["mail", "пошта", "почта"],
        "google-maps": ["google maps", "гугл мапи", "гугл карты"]
    ]

    static let communicationAliases: [String: Set<String>] = [
        "whatsapp": applicationAliases["whatsapp"]!,
        "viber": applicationAliases["viber"]!,
        "telegram": applicationAliases["telegram"]!,
        "messages": ["messages", "imessage", "sms", "смс", "повідомлення", "повідомлень", "меседж", "месседж"],
        "email": ["email", "mail", "пошта", "пошту", "почта", "почту"],
        "telephone": ["phone", "cellular", "телефон", "телефоном", "мобільний", "мобильный"]
    ]

    /// Context-only acoustic evidence. These values improve ASR hypotheses but
    /// are not resolver aliases, so a noisy fragment cannot cause an action.
    static let acousticContextOnly = [
        "Baldinini", "Балдинини", "Pierre Cardin", "бані", "баді", "Buddy", "Bady",
        "QR", "QR-код", "Q Club", "Q-клуб", "Quad", "OCR", "PDF",
        "розпізнай", "розпізнає", "відскануй", "відсканував", "проскануй",
        "про скануй", "оцифруй", "обчисли", "відкрий", "запусти", "покажи",
        "перейди", "збільш"
    ]

    static var speechVocabulary: [String] {
        let aliases = applicationAliases.values.flatMap(Array.init)
            + communicationAliases.values.flatMap(Array.init)
        return Array(Set(aliases + acousticContextOnly)).sorted()
    }

    static func applicationID(in text: String) -> String? {
        if let exact = exactValue(in: text, registry: applicationAliases) { return exact }
        // Fuzzy fallback for recogniser variants ("телега", "вайбєр", "вацап",
        // "ютьюб"): match on a stable stem instead of an exact alias.
        let normalized = " " + normalize(text) + " "
        let stems: [(String, [String])] = [
            ("telegram", ["телег", "теліг", "telegram", "telega"]),
            ("viber", ["вайб", "віб", "viber"]),
            ("whatsapp", ["ватс", "вотс", "вацап", "whats"]),
            ("youtube", ["ютуб", "ютьюб", "youtube"]),
        ]
        for (identifier, prefixes) in stems where prefixes.contains(where: { normalized.contains($0) }) {
            return identifier
        }
        return nil
    }

    static func communicationChannel(in text: String) -> String? {
        exactValue(in: text, registry: communicationAliases)
    }

    static func aliases(for applicationID: String) -> Set<String> {
        applicationAliases[applicationID] ?? [applicationID]
    }

    private static func exactValue(in text: String, registry: [String: Set<String>]) -> String? {
        let normalized = " " + normalize(text) + " "
        let matches = registry.compactMap { id, aliases -> (String, Int)? in
            aliases.map(normalize).filter { !$0.isEmpty && normalized.contains(" \($0) ") }
                .map(\.count).max().map { (id, $0) }
        }.sorted { lhs, rhs in lhs.1 > rhs.1 }
        guard let first = matches.first,
              matches.dropFirst().first?.1 != first.1 else { return nil }
        return first.0
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "uk_UA"))
            .lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct DeviceApplicationDescriptor: Equatable, Sendable {
    let id: String
    let aliases: Set<String>
    let launchURL: URL
    let exactContext: (@Sendable (String) -> URL?)?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.aliases == rhs.aliases && lhs.launchURL == rhs.launchURL
    }
}

enum DeviceApplicationResolution: Equatable, Sendable {
    case direct(DeviceApplicationDescriptor)
    case clarification([String])
    case unsupported
}

struct DeviceApplicationResolver: Sendable {
    let applications: [DeviceApplicationDescriptor]

    func resolve(spokenName: String) -> DeviceApplicationResolution {
        let normalizedName = Self.normalize(spokenName)
        if normalizedName.count < 5 {
            let exact = applications.filter { application in
                application.aliases.map(Self.normalize).contains(normalizedName) ||
                    Self.normalize(application.id) == normalizedName
            }
            if exact.count == 1, let app = exact.first { return .direct(app) }
            if exact.count > 1 { return .clarification(exact.map(\.id).sorted()) }
            return .unsupported
        }
        let domain = applications.map {
            ScopedEntityCandidate(value: $0, displayName: $0.id, aliases: Set($0.aliases.map(Self.normalize)))
        }
        // Weak phonetic overlap with unrelated installed apps is not a useful
        // clarification. Keep direct clipped-name recovery, but require every
        // rendered ambiguity to clear a stronger app-identity floor.
        let resolver = ContextScopedEntityResolver(
            candidates: domain,
            directThreshold: 0.72,
            ambiguityThreshold: 0.65,
            requiredMargin: 0.12
        )
        switch resolver.resolve(normalizedName) {
        case let .resolved(app): return .direct(app)
        case let .ambiguous(names): return .clarification(names)
        case .unresolved: return .unsupported
        }
    }

    private static func normalize(_ value: String) -> String {
        var words = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        let rawPrefixes = [["the", "app"], ["сайт", "компании"], ["програму"], ["программа"], ["приложение"], ["app"], ["сайт"], ["website"], ["site"]]
        let prefixes = rawPrefixes.map { prefix in prefix.map { token in token.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased() } }
        if let prefix = prefixes.first(where: { candidate in words.starts(with: candidate) }) { words.removeFirst(prefix.count) }
        return words.joined(separator: " ")
    }
}

enum UniversalCommandRoute: Equatable, Sendable {
    case local(LocalActionRoute)
    case deviceApplication(DeviceApplicationDescriptor, destination: URL, silent: Bool)
    case externalCapability(CommandIntent)
    case clarification([String])
    case unsupported(reason: String)
}

struct UniversalDeviceCommandRouter: Sendable {
    let local = LocalActionRouter()
    let applications: DeviceApplicationResolver

    func route(_ command: StructuredCommand, exactContext: String? = nil) -> UniversalCommandRoute {
        let localRoute = local.route(command)
        if localRoute.depth != .unavailable { return .local(localRoute) }
        if command.intent == .open || command.intent == .appAction,
           let name = command.entities["app"] {
            switch applications.resolve(spokenName: name) {
            case let .direct(app):
                let destination = exactContext.flatMap { app.exactContext?($0) } ?? app.launchURL
                return .deviceApplication(app, destination: destination, silent: true)
            case let .clarification(ids): return .clarification(ids)
            case .unsupported: return .unsupported(reason: "no_verified_public_app_mechanism")
            }
        }
        let external: Set<CommandIntent> = [.placeSearch, .productSearch, .fashionDiscovery, .groceryBasket,
            .serviceSearch, .restaurantSearch, .reservation, .taxiSearch, .taxiCompare, .navigation,
            .routeSearch, .routeAwareSearch, .weather, .publicTransport, .transportRoute, .ticketSearch,
            .ticketPurchaseHandoff, .hotelSearch, .travelPlan]
        if external.contains(command.intent) { return .externalCapability(command.intent) }
        return .unsupported(reason: "no_verified_public_capability")
    }
}

enum LaunchDeviceApplications {
    static let verified: [DeviceApplicationDescriptor] = [
        .init(id: "apple-website", aliases: ["apple", "епл"], launchURL: URL(string: "https://www.apple.com/ua/")!, exactContext: nil),
        .init(id: "spotify", aliases: CanonicalSpeechEntityRegistry.aliases(for: "spotify"), launchURL: URL(string: "spotify://")!, exactContext: nil),
        .init(id: "apple-music", aliases: CanonicalSpeechEntityRegistry.aliases(for: "apple-music"), launchURL: URL(string: "https://music.apple.com")!, exactContext: nil),
        // WhatsApp documents this public app-opening scheme. Keeping it in the
        // verified registry lets the existing scoped resolver recover clipped
        // app names without a transcript-specific substitution.
        .init(id: "whatsapp", aliases: CanonicalSpeechEntityRegistry.aliases(for: "whatsapp"), launchURL: URL(string: "whatsapp://app")!, exactContext: nil),
        .init(id: "telegram", aliases: CanonicalSpeechEntityRegistry.aliases(for: "telegram"),
              launchURL: URL(string: "tg://")!, exactContext: { value in
                  var components = URLComponents(string: "tg://resolve")
                  components?.queryItems = [.init(name: "domain", value: value)]
                  return components?.url
              }),
        // A root launch carries no unsupported contact/page parameters and
        // therefore avoids Viber's "page unavailable" intermediate screen.
        .init(id: "viber", aliases: CanonicalSpeechEntityRegistry.aliases(for: "viber"), launchURL: URL(string: "viber://")!, exactContext: nil),
        // Messages has no public "open app" scheme; `sms:` opens the composer,
        // which is the only supported entry point.
        .init(id: "messages", aliases: CanonicalSpeechEntityRegistry.aliases(for: "messages"), launchURL: URL(string: "sms:")!, exactContext: nil),
        // Only the app's own settings page is public; system panes are not.
        .init(id: "settings", aliases: CanonicalSpeechEntityRegistry.aliases(for: "settings"),
              launchURL: URL(string: "app-settings:")!, exactContext: nil),
        .init(id: "youtube", aliases: CanonicalSpeechEntityRegistry.aliases(for: "youtube"), launchURL: URL(string: "https://www.youtube.com")!, exactContext: nil),
        .init(id: "app-store", aliases: ["app store", "ап стор", "магазин застосунків"], launchURL: URL(string: "https://apps.apple.com")!, exactContext: nil),
        .init(id: "mail", aliases: CanonicalSpeechEntityRegistry.aliases(for: "mail"), launchURL: URL(string: "mailto:")!, exactContext: nil),
        .init(id: "google-maps", aliases: CanonicalSpeechEntityRegistry.aliases(for: "google-maps"),
              launchURL: URL(string: "https://www.google.com/maps")!, exactContext: { query in
                  var components = URLComponents(string: "https://www.google.com/maps/search/")
                  components?.queryItems = [.init(name: "api", value: "1"), .init(name: "query", value: query)]
                  return components?.url
              })
    ]
}
