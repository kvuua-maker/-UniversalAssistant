import Foundation

enum LaunchMarketAppMatrix {
    static let verifiedAt = Date(timeIntervalSince1970: 1_788_307_200) // 2026-09-02 UTC
    static let records: [AppCapabilityRecord] = [
        record("telegram", "Telegram", [.openApp, .openExactContext, .send], [.universalLink, .urlScheme], "https://core.telegram.org/api/links", ["Message remains an editable draft until the user sends it."]),
        record("viber", "Viber", [.openApp, .openExactContext, .send], [.urlScheme], "https://developers.viber.com/docs/tools/share-button/", ["Share text is user-editable; no silent send."]),
        record("google-maps", "Google Maps", [.openApp, .openExactContext, .search, .navigate], [.universalLink], "https://developers.google.com/maps/documentation/urls/get-started", ["Maps URL handoff; no claim of reading live route state back from the app."]),
        record("waze", "Waze", [.openApp, .openExactContext, .search, .navigate], [.universalLink, .urlScheme], "https://developers.google.com/waze/deeplinks", ["Deep-link navigation only; Transport SDK requires a separate partnership."]),
        record("apple-music", "Apple Music", [.search, .read, .play, .pause], [.sdk], "https://developer.apple.com/musickit/", ["Music data and playback require MusicKit authorization and entitlement/device testing."], auth: true, status: .deviceTestRequired)
    ]
    private static func record(_ id: String, _ name: String, _ capabilities: AppCapabilities,
                               _ mechanisms: Set<AppIntegrationMechanism>, _ docs: String,
                               _ limitations: [String], auth: Bool = false,
                               status: AppCapabilityTestStatus = .documented) -> AppCapabilityRecord {
        .init(id: id, displayName: name, bundleIdentifier: nil, regions: ["UA"], minimumVersion: nil,
              capabilities: capabilities, mechanisms: mechanisms, supportedActions: [],
              authenticationRequired: auth, limitations: limitations, fallback: [.openApp],
              testStatus: status, officialDocumentationURL: URL(string: docs),
              lastOfficialVerification: verifiedAt)
    }
}
