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
        let value = Self.normalize(spokenName)
        let matches = applications.filter { app in app.aliases.map(Self.normalize).contains(value) }
        if matches.count == 1 { return .direct(matches[0]) }
        if matches.count > 1 { return .clarification(matches.map(\.id).sorted()) }

        let ranked = applications.map { app in
            let score = app.aliases.map { Self.similarity(value, Self.normalize($0)) }.max() ?? 0
            return (app, score)
        }.sorted { $0.1 > $1.1 }
        guard let best = ranked.first, best.1 >= 0.48 else { return .unsupported }
        let runnerUp = ranked.dropFirst().first?.1 ?? 0
        if best.1 >= 0.72, best.1 - runnerUp >= 0.12 { return .direct(best.0) }
        let candidates = ranked.filter { $0.1 >= max(0.48, best.1 - 0.08) }.map { $0.0.id }.sorted()
        return .clarification(candidates)
    }

    private static func similarity(_ lhs: String, _ rhs: String) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        if lhs == rhs { return 1 }
        if min(lhs.count, rhs.count) >= 5, (lhs.hasPrefix(rhs) || rhs.hasPrefix(lhs)) { return 0.84 }
        let left = Array(lhs), right = Array(rhs)
        var previous = Array(0...right.count)
        for (i, l) in left.enumerated() {
            var current = [i + 1]
            for (j, r) in right.enumerated() {
                current.append(min(current[j] + 1, previous[j + 1] + 1, previous[j] + (l == r ? 0 : 1)))
            }
            previous = current
        }
        return 1 - Double(previous[right.count]) / Double(max(left.count, right.count))
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
        .init(id: "telegram", aliases: ["telegram", "телеграм", "телега"],
              launchURL: URL(string: "tg://")!, exactContext: { value in
                  var components = URLComponents(string: "tg://resolve")
                  components?.queryItems = [.init(name: "domain", value: value)]
                  return components?.url
              }),
        .init(id: "viber", aliases: ["viber", "вайбер"], launchURL: URL(string: "viber://")!, exactContext: nil),
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
