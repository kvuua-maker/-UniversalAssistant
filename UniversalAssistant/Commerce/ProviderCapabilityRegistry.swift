import Foundation

enum ProviderImplementationStatus: String, Codable, Sendable {
    case researched, adapterReady, credentialRequired, approvalRequired
    case deviceTestRequired, implementedTested, fallback, unsupported
    case fullyImplemented, fullyTested, partnerApprovalRequired, fallbackActive, temporarilyBroken
}

struct CommerceProviderCapabilities: OptionSet, Codable, Sendable {
    let rawValue: UInt64
    static let search = Self(rawValue: 1 << 0)
    static let catalog = Self(rawValue: 1 << 1)
    static let exactProduct = Self(rawValue: 1 << 2)
    static let price = Self(rawValue: 1 << 3)
    static let availability = Self(rawValue: 1 << 4)
    static let shipping = Self(rawValue: 1 << 5)
    static let affiliateAttribution = Self(rawValue: 1 << 6)
    static let exactDeepLink = Self(rawValue: 1 << 7)
    static let appHandoff = Self(rawValue: 1 << 8)
    static let cart = Self(rawValue: 1 << 9)
    static let checkoutHandoff = Self(rawValue: 1 << 10)
}

struct ProviderCapabilityRecord: Identifiable, Equatable, Codable, Sendable {
    let id: String
    var displayName: String
    var regions: Set<String>
    var capabilities: CommerceProviderCapabilities
    var affiliateNetwork: String?
    var requiresCredentials: Bool
    var requiresOwnerRegistration: Bool
    var requiresApproval: Bool
    var rateLimitSummary: String?
    var restrictions: [String]
    var status: ProviderImplementationStatus
    var fallback: String?
    var lastOfficialVerification: Date?
    var enabled: Bool
    var officialDocumentationURL: URL? = nil
}

actor ProviderCapabilityRegistry {
    private var records: [String: ProviderCapabilityRecord]

    init(records: [ProviderCapabilityRecord] = []) {
        self.records = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
    }

    func upsert(_ record: ProviderCapabilityRecord) { records[record.id] = record }
    func record(id: String) -> ProviderCapabilityRecord? { records[id] }

    func eligible(region: String, requiring capability: CommerceProviderCapabilities) -> [ProviderCapabilityRecord] {
        records.values.filter {
            $0.enabled && $0.regions.contains(region.uppercased())
                && $0.capabilities.contains(capability)
                && [.adapterReady, .implementedTested, .fullyImplemented, .fullyTested, .fallback, .fallbackActive].contains($0.status)
        }.sorted { $0.id < $1.id }
    }
}

enum OfficialPublicProviderDomain: String, Sendable {
    case marketplace, grocery, lodging, carRental, events, cinema, jobs, transport, parcel
}

enum OfficialPublicProviderRoute: Equatable, Sendable {
    case query(base: URL, parameter: String)
    case aliExpressWholesale
    case fixed(URL)

    func destination(query: String) -> URL? {
        switch self {
        case let .query(base, parameter):
            guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
            components.queryItems = (components.queryItems ?? []) + [.init(name: parameter, value: query)]
            return components.url
        case .aliExpressWholesale:
            let slug = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: "-")
            guard !slug.isEmpty,
                  let encoded = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
            return URL(string: "https://www.aliexpress.com/w/wholesale-\(encoded).html")
        case let .fixed(url): return url
        }
    }

    var preservesQuery: Bool {
        switch self {
        case .query, .aliExpressWholesale: true
        case .fixed: false
        }
    }
}

/// Credential-free official consumer destinations. A handoff preserves the
/// request but never claims live inventory, price, availability, or completion.
struct OfficialPublicProviderHandoff: Equatable, Sendable {
    let id: String
    let displayName: String
    let aliases: Set<String>
    let domain: OfficialPublicProviderDomain
    let route: OfficialPublicProviderRoute
    let mechanism: String
    let officialEvidence: URL
    func destination(query: String) -> URL? { route.destination(query: query) }
    var preservesQuery: Bool { route.preservesQuery }
}

/// In-place extension of the canonical provider registry, not a parallel
/// discovery/execution system.
enum OfficialPublicProviderHandoffRegistry {
    static let lastVerified = Date(timeIntervalSince1970: 1_789_171_200) // 2026-09-12 UTC
    static let records: [OfficialPublicProviderHandoff] = [
        r("market.amazon", "Amazon", ["amazon"], .marketplace, .query(base: u("https://www.amazon.com/s"), parameter: "k"), "official_exact_search", "https://www.amazon.com/"),
        r("market.ebay", "eBay", ["ebay", "e bay", "ебей"], .marketplace, .query(base: u("https://www.ebay.com/sch/i.html"), parameter: "_nkw"), "official_exact_search", "https://www.ebay.com/"),
        r("market.aliexpress", "AliExpress", ["aliexpress", "ali express", "аліекспрес"], .marketplace, .aliExpressWholesale, "official_exact_search", "https://www.aliexpress.com/"),
        r("market.temu", "Temu", ["temu", "тему"], .marketplace, .query(base: u("https://www.temu.com/search_result.html"), parameter: "search_key"), "official_exact_search", "https://www.temu.com/"),
        r("market.prom", "Prom.ua", ["prom", "prom ua", "prom.ua", "пром"], .marketplace, .query(base: u("https://prom.ua/ua/search"), parameter: "search_term"), "official_exact_search", "https://support.prom.ua/hc/uk/articles/360004988457"),
        r("retail.silpo", "Сільпо", ["сільпо", "silpo"], .grocery, .query(base: u("https://silpo.ua/search"), parameter: "find"), "official_exact_search", "https://silpo.ua/"),
        r("retail.atb", "АТБ", ["атб", "atb"], .grocery, .fixed(u("https://www.atbmarket.com/catalog")), "official_catalog_with_site_search_fallback", "https://www.atbmarket.com/catalog"),
        r("retail.fora", "Фора", ["фора", "fora"], .grocery, .fixed(u("https://fora.ua/")), "official_site_with_site_search_fallback", "https://fora.ua/"),
        r("retail.fozzy", "Fozzy", ["fozzy", "фоззі", "фоззи"], .grocery, .query(base: u("https://fozzyshop.ua/search"), parameter: "q"), "official_exact_search", "https://fozzyshop.ua/"),
        r("lodging.booking", "Booking.com", ["booking", "booking.com", "букінг"], .lodging, .query(base: u("https://www.booking.com/searchresults.html"), parameter: "ss"), "official_destination_search", "https://www.booking.com/"),
        r("lodging.dobovo", "Dobovo", ["dobovo", "добово"], .lodging, .fixed(u("https://www.dobovo.com/ukraine.html")), "official_filtered_catalog", "https://www.dobovo.com/ukraine.html"),
        r("rental.getmancar", "Getmancar", ["getmancar", "get man car", "гетманкар"], .carRental, .fixed(u("https://getmancar.com/uk")), "official_rental_search", "https://getmancar.com/uk"),
        r("events.karabas", "KARABAS", ["karabas", "карабас"], .events, .fixed(u("https://karabas.com/")), "official_city_event_catalog", "https://karabas.com/"),
        r("cinema.multiplex", "Multiplex", ["multiplex", "мультиплекс"], .cinema, .fixed(u("https://multiplex.ua/movies")), "official_movie_schedule", "https://multiplex.ua/movies"),
        r("cinema.planetakino", "Планета Кіно", ["планета кіно", "planeta kino", "planetakino"], .cinema, .fixed(u("https://planetakino.ua/")), "official_movie_schedule", "https://planetakino.ua/"),
        r("jobs.workua", "Work.ua", ["work ua", "work.ua"], .jobs, .query(base: u("https://www.work.ua/jobs/"), parameter: "search"), "official_job_search", "https://www.work.ua/jobs/"),
        r("jobs.robotaua", "robota.ua", ["robota ua", "robota.ua"], .jobs, .query(base: u("https://robota.ua/zapros/"), parameter: "query"), "official_job_search", "https://robota.ua/zapros/"),
        r("jobs.jobsua", "Jobs.ua", ["jobs ua", "jobs.ua"], .jobs, .query(base: u("https://jobs.ua/vacancy"), parameter: "search"), "official_job_search", "https://jobs.ua/vacancy"),
        r("jobs.dcz", "Державна служба зайнятості", ["служба зайнятості", "dcz"], .jobs, .fixed(u("https://dcz.gov.ua/job")), "official_job_catalog", "https://dcz.gov.ua/job"),
        r("jobs.djinni", "Djinni", ["djinni", "джині"], .jobs, .query(base: u("https://djinni.co/jobs/"), parameter: "keywords"), "official_job_search", "https://djinni.co/jobs/"),
        r("jobs.dou", "DOU Jobs", ["dou", "dou jobs"], .jobs, .query(base: u("https://jobs.dou.ua/vacancies/"), parameter: "search"), "official_job_search", "https://jobs.dou.ua/vacancies/"),
        r("jobs.happymonday", "Happy Monday", ["happy monday", "happymonday"], .jobs, .query(base: u("https://happymonday.ua/jobs-search"), parameter: "query"), "official_job_search", "https://happymonday.ua/jobs-search"),
        r("transport.uz", "Укрзалізниця", ["укрзалізниця", "uz", "ukrzaliznytsia"], .transport, .fixed(u("https://booking.uz.gov.ua/")), "official_ticket_search", "https://booking.uz.gov.ua/"),
        r("parcel.novaposhta", "Нова пошта", ["нова пошта", "nova poshta"], .parcel, .fixed(u("https://tracking.novaposhta.ua/")), "official_tracking_form", "https://tracking.novaposhta.ua/"),
        r("parcel.ukrposhta", "Укрпошта", ["укрпошта", "ukrposhta"], .parcel, .fixed(u("https://track.ukrposhta.ua/tracking_UA.html")), "official_tracking_form", "https://track.ukrposhta.ua/tracking_UA.html"),
        r("parcel.meest", "Meest", ["meest", "meest пошта"], .parcel, .fixed(u("https://ua.meest.com/parcel-track")), "official_tracking_form", "https://ua.meest.com/parcel-track")
    ]

    static func records(in domain: OfficialPublicProviderDomain) -> [OfficialPublicProviderHandoff] {
        records.filter { $0.domain == domain }
    }

    private static func u(_ value: String) -> URL { URL(string: value)! }
    private static func r(_ id: String, _ name: String, _ aliases: Set<String>,
                          _ domain: OfficialPublicProviderDomain, _ route: OfficialPublicProviderRoute,
                          _ mechanism: String, _ evidence: String) -> OfficialPublicProviderHandoff {
        .init(id: id, displayName: name, aliases: aliases, domain: domain, route: route,
              mechanism: mechanism, officialEvidence: u(evidence))
    }
}

protocol RetailProvider: Sendable {
    var providerID: String { get }
    func search(_ request: RetailSearchRequest) async throws -> [NormalizedOffer]
}

enum RetailFulfillmentPreference: String, Equatable, Codable, Sendable {
    case pickup, delivery, either
}

struct RetailSearchLocation: Equatable, Codable, Sendable {
    let latitude: Double
    let longitude: Double
    var radiusMeters: Double

    func validated() throws -> Self {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude),
              (100...100_000).contains(radiusMeters) else { throw RetailProviderError.invalidRequest }
        return self
    }
}

struct RetailPriceRange: Equatable, Codable, Sendable {
    var minimum: Money?
    var maximum: Money?

    func validated() throws -> Self {
        guard minimum?.amount ?? 0 >= 0, maximum?.amount ?? 0 >= 0 else { throw RetailProviderError.invalidRequest }
        if let minimum, let maximum {
            guard minimum.currency == maximum.currency, minimum.amount <= maximum.amount else {
                throw RetailProviderError.invalidRequest
            }
        }
        return self
    }
}

struct RetailSearchRequest: Equatable, Sendable {
    let identity: ProductIdentity
    var region: String = "UA"
    var limit: Int = 20
    var priceRange: RetailPriceRange? = nil
    var fulfillment: RetailFulfillmentPreference = .either
    var location: RetailSearchLocation? = nil

    func validated() throws -> Self {
        _ = try identity.validated()
        guard (1...50).contains(limit), region.count == 2 else { throw RetailProviderError.invalidRequest }
        if let priceRange { _ = try priceRange.validated() }
        if let location { _ = try location.validated() }
        return self
    }
}

enum RetailProviderError: Error, Equatable, Sendable { case invalidRequest, unavailable }
