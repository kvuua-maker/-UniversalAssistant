import Foundation

enum MediaItemKind: String, Codable, Sendable { case song, album, artist, playlist, station }
struct MediaItem: Identifiable, Equatable, Sendable {
    let id: String; let providerID: String; let kind: MediaItemKind
    let title: String; let artist: String?; let exactURL: URL?
}
enum MediaAuthorizationState: String, Equatable, Sendable { case authorized, denied, notDetermined, restricted }
enum MediaControlAction: String, Sendable { case play, pause, resume, next, previous }
enum MediaActionState: String, Equatable, Sendable { case playing, paused, resumed, advanced, rewound, destinationPrepared }
struct MediaActionResult: Equatable, Sendable { let providerID: String; let itemID: String?; let state: MediaActionState; let destination: URL? }
enum MediaIntegrationError: Error, Equatable, Sendable { case invalidRequest, authorizationRequired, unsupportedAction, unmanagedPlayback, invalidDestination, playbackNotStarted }

protocol MediaProviderAdapter: Sendable {
    var providerID: String { get }
    func authorizationState() async -> MediaAuthorizationState
    func requestAuthorization() async -> MediaAuthorizationState
    func search(query: String, kinds: Set<MediaItemKind>, limit: Int) async throws -> [MediaItem]
    func control(_ action: MediaControlAction, item: MediaItem?) async throws
    func playCurrent() async throws
    func playbackState() async -> MediaActionState?
}
extension MediaProviderAdapter {
    func playCurrent() async throws { throw MediaIntegrationError.unsupportedAction }
    func playbackState() async -> MediaActionState? { nil }
}

actor MediaIntegrationEngine {
    private let adapters: [String: any MediaProviderAdapter]
    private var managedProviderID: String?
    init(adapters: [any MediaProviderAdapter]) { self.adapters = Dictionary(uniqueKeysWithValues: adapters.map { ($0.providerID, $0) }) }

    func search(providerID: String, query: String, kinds: Set<MediaItemKind>, limit: Int = 20,
                requestAuthorization: Bool = false) async throws -> [MediaItem] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !kinds.isEmpty, (1...50).contains(limit), let adapter = adapters[providerID] else { throw MediaIntegrationError.invalidRequest }
        var state = await adapter.authorizationState()
        if state == .notDetermined && requestAuthorization { state = await adapter.requestAuthorization() }
        guard state == .authorized else { throw MediaIntegrationError.authorizationRequired }
        return try await adapter.search(query: text, kinds: kinds, limit: limit).filter { $0.providerID == providerID && !$0.id.isEmpty }
    }

    func play(_ item: MediaItem) async throws -> MediaActionResult {
        guard let adapter = adapters[item.providerID], await adapter.authorizationState() == .authorized else { throw MediaIntegrationError.authorizationRequired }
        try await adapter.control(.play, item: item); managedProviderID = item.providerID
        return .init(providerID: item.providerID, itemID: item.id, state: .playing, destination: nil)
    }

    func playCurrent(providerID: String) async throws -> MediaActionResult {
        guard let adapter = adapters[providerID] else { throw MediaIntegrationError.invalidRequest }
        var state = await adapter.authorizationState()
        if state == .notDetermined { state = await adapter.requestAuthorization() }
        guard state == .authorized else { throw MediaIntegrationError.authorizationRequired }
        try await adapter.playCurrent()
        guard await adapter.playbackState() == .playing else {
            throw MediaIntegrationError.playbackNotStarted
        }
        managedProviderID = providerID
        return .init(providerID: providerID, itemID: nil, state: .playing, destination: nil)
    }

    func control(_ action: MediaControlAction) async throws -> MediaActionResult {
        guard action != .play else { throw MediaIntegrationError.invalidRequest }
        guard let providerID = managedProviderID, let adapter = adapters[providerID] else { throw MediaIntegrationError.unmanagedPlayback }
        try await adapter.control(action, item: nil)
        let state: MediaActionState = switch action { case .pause: .paused; case .resume: .resumed; case .next: .advanced; case .previous: .rewound; case .play: .playing }
        return .init(providerID: providerID, itemID: nil, state: state, destination: nil)
    }

    func handoff(_ item: MediaItem) throws -> MediaActionResult {
        guard let url = item.exactURL, url.scheme == "https", url.host != nil, !url.path.isEmpty, url.path != "/" else { throw MediaIntegrationError.invalidDestination }
        return .init(providerID: item.providerID, itemID: item.id, state: .destinationPrepared, destination: url)
    }
}

#if canImport(MusicKit)
@preconcurrency import MusicKit
struct AppleMusicAuthorizationGateway: Sendable {
    func current() -> MediaAuthorizationState { map(MusicAuthorization.currentStatus) }
    func request() async -> MediaAuthorizationState { map(await MusicAuthorization.request()) }
    private func map(_ status: MusicAuthorization.Status) -> MediaAuthorizationState {
        switch status { case .authorized: .authorized; case .denied: .denied; case .restricted: .restricted; case .notDetermined: .notDetermined; @unknown default: .restricted }
    }
}

@MainActor final class AppleMusicProviderAdapter: @preconcurrency MediaProviderAdapter {
    nonisolated let providerID = "apple-music"
    private let player = ApplicationMusicPlayer.shared
    private let systemPlayer = SystemMusicPlayer.shared
    private enum PlaybackSource { case application, system }
    private var playbackSource: PlaybackSource?

    func authorizationState() -> MediaAuthorizationState { AppleMusicAuthorizationGateway().current() }
    func requestAuthorization() async -> MediaAuthorizationState { await AppleMusicAuthorizationGateway().request() }

    func search(query: String, kinds: Set<MediaItemKind>, limit: Int) async throws -> [MediaItem] {
        var request = MusicCatalogSearchRequest(term: query, types: [Song.self, Album.self, Artist.self, Playlist.self, Station.self])
        request.limit = limit
        let response = try await request.response()
        var items: [MediaItem] = []
        if kinds.contains(.song) { items += response.songs.map { .init(id: $0.id.rawValue, providerID: providerID, kind: .song, title: $0.title, artist: $0.artistName, exactURL: $0.url) } }
        if kinds.contains(.album) { items += response.albums.map { .init(id: $0.id.rawValue, providerID: providerID, kind: .album, title: $0.title, artist: $0.artistName, exactURL: $0.url) } }
        if kinds.contains(.artist) { items += response.artists.map { .init(id: $0.id.rawValue, providerID: providerID, kind: .artist, title: $0.name, artist: nil, exactURL: $0.url) } }
        if kinds.contains(.playlist) { items += response.playlists.map { .init(id: $0.id.rawValue, providerID: providerID, kind: .playlist, title: $0.name, artist: $0.curatorName, exactURL: $0.url) } }
        if kinds.contains(.station) { items += response.stations.map { .init(id: $0.id.rawValue, providerID: providerID, kind: .station, title: $0.name, artist: nil, exactURL: $0.url) } }
        return Array(items.prefix(limit))
    }

    func control(_ action: MediaControlAction, item: MediaItem?) async throws {
        switch action {
        case .play:
            guard let item else { throw MediaIntegrationError.invalidRequest }
            let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(item.id))
            guard let song = try await request.response().items.first else { throw MediaIntegrationError.invalidRequest }
            player.queue = [song]
            try await player.play()
            playbackSource = .application
        case .pause: player.pause()
        case .resume: try await player.play()
        case .next: try await player.skipToNextEntry()
        case .previous: try await player.skipToPreviousEntry()
        }
    }


    func playCurrent() async throws {
        try await systemPlayer.play()
        playbackSource = .system
    }

    func playbackState() -> MediaActionState? {
        guard let playbackSource else { return nil }
        let status = switch playbackSource {
        case .application: player.state.playbackStatus
        case .system: systemPlayer.state.playbackStatus
        }
        return status == .playing ? .playing : nil
    }
}
#endif
