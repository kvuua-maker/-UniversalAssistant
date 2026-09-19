import Foundation
import Testing
@testable import UniversalAssistant

private actor MediaFixture: MediaProviderAdapter {
    let providerID: String; var state: MediaAuthorizationState; let items: [MediaItem]
    private(set) var actions: [MediaControlAction] = []
    private(set) var currentPlaybackRequests = 0
    init(_ id: String = "apple-music", state: MediaAuthorizationState = .authorized, items: [MediaItem] = []) { providerID = id; self.state = state; self.items = items }
    func authorizationState() -> MediaAuthorizationState { state }
    func requestAuthorization() -> MediaAuthorizationState { state }
    func search(query: String, kinds: Set<MediaItemKind>, limit: Int) -> [MediaItem] { Array(items.filter { kinds.contains($0.kind) }.prefix(limit)) }
    func control(_ action: MediaControlAction, item: MediaItem?) { actions.append(action) }
    func playCurrent() { currentPlaybackRequests += 1 }
    func playbackState() -> MediaActionState? { currentPlaybackRequests > 0 ? .playing : nil }
}
private func mediaItem(provider: String = "apple-music") -> MediaItem { .init(id: "song-1", providerID: provider, kind: .song, title: "Song", artist: "Artist", exactURL: URL(string: "https://music.apple.com/ua/song/song-1")) }

@Suite("Truthful media integration") struct MediaIntegrationEngineTests {
    @Test func searchRequiresAuthorizationAndExactProviderEvidence() async throws {
        let denied = MediaFixture(state: .denied), engine = MediaIntegrationEngine(adapters: [denied])
        await #expect(throws: MediaIntegrationError.authorizationRequired) { try await engine.search(providerID: "apple-music", query: "Song", kinds: [.song]) }
    }
    @Test func managedPlaybackCanBePausedAndResumed() async throws {
        let adapter = MediaFixture(items: [mediaItem()]), engine = MediaIntegrationEngine(adapters: [adapter])
        _ = try await engine.play(mediaItem()); #expect(try await engine.control(.pause).state == .paused); #expect(try await engine.control(.resume).state == .resumed)
    }
    @Test func currentSystemPlaybackMustBeObservedAsPlaying() async throws {
        let adapter = MediaFixture(), engine = MediaIntegrationEngine(adapters: [adapter])
        let value = try await engine.playCurrent(providerID: "apple-music")
        #expect(value.state == .playing)
        #expect(await adapter.currentPlaybackRequests == 1)
    }
    @Test func unrelatedPlaybackCannotBeControlled() async throws {
        let engine = MediaIntegrationEngine(adapters: [MediaFixture()])
        await #expect(throws: MediaIntegrationError.unmanagedPlayback) { try await engine.control(.pause) }
    }
    @Test func providerHandoffRequiresExactHTTPSItem() async throws {
        let engine = MediaIntegrationEngine(adapters: [])
        #expect(try await engine.handoff(mediaItem()).state == .destinationPrepared)
        let bad = MediaItem(id: "x", providerID: "spotify", kind: .song, title: "x", artist: nil, exactURL: URL(string: "https://open.spotify.com/"))
        await #expect(throws: MediaIntegrationError.invalidDestination) { try await engine.handoff(bad) }
    }
}
