import Foundation

enum ConnectableServiceStatus: String, Equatable, Sendable {
    case configurationRequired
    case providerCredentialRequired
    case available
}

struct ConnectableServiceDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let authorization: ProviderAuthorizationMethod
    let status: ConnectableServiceStatus
    let capabilitySummary: String
    let acceptsThirdPartyPassword: Bool
}

/// Only services with a verified official consent/token boundary appear here.
/// Partner-only publisher credentials are deliberately not user connections.
enum ConnectableServiceRegistry {
    static let records: [ConnectableServiceDescriptor] = [
        .init(id: "google", displayName: "Google", authorization: .oauth,
              status: .configurationRequired, capabilitySummary: "Gmail, Google Calendar, Google Drive",
              acceptsThirdPartyPassword: false),
        .init(id: "ebay", displayName: "eBay", authorization: .oauth,
              status: .configurationRequired, capabilitySummary: "Дані й дії облікового запису eBay",
              acceptsThirdPartyPassword: false),
        .init(id: "nova-poshta", displayName: "Нова пошта", authorization: .officialAuthenticatedHandoff,
              status: .providerCredentialRequired, capabilitySummary: "Авторизовані відправлення за API key",
              acceptsThirdPartyPassword: false),
        .init(id: "meest", displayName: "Meest", authorization: .officialAuthenticatedHandoff,
              status: .providerCredentialRequired, capabilitySummary: "Контрактні відправлення за API token",
              acceptsThirdPartyPassword: false),
        .init(id: "ukrposhta", displayName: "Укрпошта", authorization: .officialAuthenticatedHandoff,
              status: .providerCredentialRequired, capabilitySummary: "API-відправлення за contract token",
              acceptsThirdPartyPassword: false)
    ]
}
