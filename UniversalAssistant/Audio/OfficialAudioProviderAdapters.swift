import Foundation

protocol AudioProviderHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

enum OfficialAudioAdapterError: Error, Equatable { case invalidEndpoint, unauthorized, rejected(Int), malformedResponse }

struct SonosControlAPIAdapter: AudioDeviceProviderAdapter {
    let providerID = "sonos"
    let householdID: String
    let groupID: String
    let bearerToken: String
    let transport: any AudioProviderHTTPTransport

    func snapshot(for device: AudioDeviceIdentity) async throws -> AudioDeviceSnapshot {
        let data = try await request(path: "groups/\(groupID)/playback")
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw OfficialAudioAdapterError.malformedResponse }
        return .init(identity: device, volume: nil, muted: nil, playback: object["playbackState"] as? String,
                     metadataTitle: nil, batteryPercent: nil, observedAt: Date())
    }
    func execute(_ command: AudioDeviceCommand) async throws {
        let action: String
        switch command.kind { case .play: action = "play"; case .pause: action = "pause"; case .next: action = "skipToNextTrack"; case .previous: action = "skipToPreviousTrack"; default: throw AudioCapabilityRegistryError.unsupported }
        _ = try await request(path: "groups/\(groupID)/playback/\(action)", method: "POST")
    }
    private func request(path: String, method: String = "GET") async throws -> Data {
        guard let url = URL(string: "https://api.ws.sonos.com/control/api/v1/households/\(householdID)/\(path)") else { throw OfficialAudioAdapterError.invalidEndpoint }
        var request = URLRequest(url: url); request.httpMethod = method
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else { throw OfficialAudioAdapterError.rejected(response.statusCode) }
        return data
    }
}

struct HEOSCommandEncoder: Sendable {
    func command(_ name: String, parameters: [String: String]) throws -> String {
        let allowed = Set(["heos://player/get_players", "heos://player/get_play_state", "heos://player/set_play_state", "heos://player/get_volume", "heos://player/set_volume", "heos://player/set_mute", "heos://player/play_next", "heos://player/play_previous", "heos://player/get_now_playing_media", "heos://player/get_play_mode", "heos://player/set_play_mode", "heos://browse/get_music_sources"])
        guard allowed.contains(name) else { throw AudioCapabilityRegistryError.unsupported }
        let query = parameters.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }.joined(separator: "&")
        return query.isEmpty ? name : "\(name)&\(query)"
    }
}
