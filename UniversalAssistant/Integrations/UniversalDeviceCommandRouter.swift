import Foundation

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
        .init(id: "spotify", aliases: ["spotify", "спотіфай", "спотифай"], launchURL: URL(string: "spotify://")!, exactContext: nil),
        .init(id: "apple-music", aliases: ["apple music", "епл мюзік", "эппл мьюзик"], launchURL: URL(string: "https://music.apple.com")!, exactContext: nil),
        // WhatsApp documents this public app-opening scheme. Keeping it in the
        // verified registry lets the existing scoped resolver recover clipped
        // app names without a transcript-specific substitution.
        .init(id: "whatsapp", aliases: ["whatsapp"], launchURL: URL(string: "whatsapp://app")!, exactContext: nil),
        .init(id: "telegram", aliases: ["telegram", "телеграм", "телега"],
              launchURL: URL(string: "tg://")!, exactContext: { value in
                  var components = URLComponents(string: "tg://resolve")
                  components?.queryItems = [.init(name: "domain", value: value)]
                  return components?.url
              }),
        // A root launch carries no unsupported contact/page parameters and
        // therefore avoids Viber's "page unavailable" intermediate screen.
        .init(id: "viber", aliases: ["viber", "вайбер", "вібер"], launchURL: URL(string: "viber://")!, exactContext: nil),
        .init(id: "youtube", aliases: ["youtube", "ютуб"], launchURL: URL(string: "https://www.youtube.com")!, exactContext: nil),
        .init(id: "app-store", aliases: ["app store", "ап стор", "магазин застосунків"], launchURL: URL(string: "https://apps.apple.com")!, exactContext: nil),
        .init(id: "mail", aliases: ["mail", "пошта", "почта"], launchURL: URL(string: "mailto:")!, exactContext: nil),
        .init(id: "google-maps", aliases: ["google maps", "гугл мапи", "гугл карты"],
              launchURL: URL(string: "https://www.google.com/maps")!, exactContext: { query in
                  var components = URLComponents(string: "https://www.google.com/maps/search/")
                  components?.queryItems = [.init(name: "api", value: "1"), .init(name: "query", value: query)]
                  return components?.url
              })
    ]
}
