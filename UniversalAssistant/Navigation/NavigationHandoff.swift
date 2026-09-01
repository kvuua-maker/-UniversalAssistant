import Foundation

enum NavigationProvider: String, Codable, CaseIterable, Sendable { case appleMaps, googleMaps, waze }

protocol NavigationPreferencePersisting: Sendable {
    func load() async throws -> NavigationProvider?
    func save(_ provider: NavigationProvider) async throws
}

actor LocalNavigationPreferencePersistence: NavigationPreferencePersisting {
    private let store: LocalStore
    init(store: LocalStore = .shared) { self.store = store }
    func load() async throws -> NavigationProvider? { try await store.load(NavigationProvider.self, from: "default-navigation-provider.json") }
    func save(_ provider: NavigationProvider) async throws { try await store.save(provider, as: "default-navigation-provider.json") }
}

actor NavigationPreferences {
    private let persistence: any NavigationPreferencePersisting
    private(set) var defaultProvider: NavigationProvider = .appleMaps
    init(persistence: any NavigationPreferencePersisting = LocalNavigationPreferencePersistence()) { self.persistence = persistence }
    func restore() async throws { defaultProvider = try await persistence.load() ?? .appleMaps }
    func setDefault(_ provider: NavigationProvider) async throws { try await persistence.save(provider); defaultProvider = provider }
}

struct NavigationHandoff: Sendable {
    func url(provider: NavigationProvider, destination: RoutePoint, mode: TravelMode) throws -> URL {
        guard (-90...90).contains(destination.latitude), (-180...180).contains(destination.longitude) else { throw RouteError.invalidCoordinate }
        let coordinate = "\(destination.latitude),\(destination.longitude)"
        var components: URLComponents
        switch provider {
        case .appleMaps:
            components = URLComponents(string: "https://maps.apple.com/")!
            components.queryItems = [.init(name: "daddr", value: coordinate), .init(name: "dirflg", value: appleMode(mode))]
        case .googleMaps:
            components = URLComponents(string: "https://www.google.com/maps/dir/")!
            components.queryItems = [.init(name: "api", value: "1"), .init(name: "destination", value: coordinate), .init(name: "travelmode", value: mode.rawValue), .init(name: "dir_action", value: "navigate")]
        case .waze:
            components = URLComponents(string: "https://waze.com/ul")!
            components.queryItems = [.init(name: "ll", value: coordinate), .init(name: "navigate", value: "yes"), .init(name: "utm_source", value: "UniversalAssistant")]
        }
        guard let url = components.url else { throw RouteError.invalidCoordinate }
        return url
    }
    private func appleMode(_ mode: TravelMode) -> String { switch mode { case .driving: "d"; case .walking: "w"; case .transit: "r" } }
}
