import Foundation

enum CanonicalPartnerDecision: String, Codable, Sendable {
    case affiliateActive = "AFFILIATE_ACTIVE"
    case affiliateReadyOwnerAction = "AFFILIATE_READY_OWNER_ACTION"
    case functionalNoAffiliateProgram = "FUNCTIONAL_NO_AFFILIATE_PROGRAM"
    case paidPartnerAccessNotConnected = "PAID_PARTNER_ACCESS_NOT_CONNECTED"
    case unsupported = "UNSUPPORTED"
    case unknown = "UNKNOWN"
}

struct CanonicalPartnerPolicy: Identifiable, Equatable, Sendable {
    let id: String
    let providerID: String
    let displayName: String
    let decision: CanonicalPartnerDecision
    let networkOrMechanism: String
    let supportsExactDestination: Bool
    let supportsCampaignOrSubID: Bool
    let requiresOwnerAction: Bool
    let costToUniversalAssistant: Decimal
    let requiresExplicitUserActivation: Bool
    let officialEvidence: URL
    let verifiedAt: Date
}

/// Audited policy for the existing attribution router, not a second provider
/// system. No record is active until approved credentials and production
/// attribution evidence exist.
enum CanonicalPartnerPolicyRegistry {
    static let verifiedAt = Date(timeIntervalSince1970: 1_789_257_600) // 2026-09-13 UTC

    static let records: [CanonicalPartnerPolicy] = {
        let directReady: [(String, String, String, String, Bool)] = [
            ("market.amazon", "Amazon", "Amazon Associates", "https://affiliate-program.amazon.com/help/operating/agreement", true),
            ("market.ebay", "eBay", "eBay Partner Network", "https://partnernetwork.ebay.com/solutions/creating-affiliate-links", false),
            ("market.aliexpress", "AliExpress", "AliExpress Portals", "https://cdn.contract.alibaba.com/terms/b_platform_service_agreement/20250305142526766/20250305142526766.html?lng=en", false),
            ("market.temu", "Temu", "Temu Partner Platform", "https://partner-eu.temu.com/documentation?menu_code=633a8618bf544adabf411a1a07ac7b69", false),
            ("retail.atb", "АТБ", "Admitad", "https://www.admitad.com/ua/store/offers/atb-ua/", false),
            ("lodging.booking", "Booking.com", "Booking.com Affiliate Partner Program", "https://www.booking.com/affiliate-program/v2/index.en-gb.html", false),
            ("lodging.dobovo", "Dobovo", "Dobovo affiliate program", "https://www.dobovo.com/agents/", false),
            ("events.karabas", "KARABAS", "KARABAS partner network", "https://all.karabas.com/en/promoter/", false),
            ("appointments.altegio", "Altegio", "Altegio partner/developer program", "https://developer.alteg.io/en/partners", false),
            ("travel.expedia", "Expedia", "Expedia Travel Creator Program", "https://partner.expediagroup.com/en-us/solutions/explore-our-affiliate-program", false),
            ("travel.hotels", "Hotels.com", "Expedia Travel Creator Program", "https://partner.expediagroup.com/en-us/solutions/explore-our-affiliate-program", false),
            ("travel.vrbo", "Vrbo", "Expedia Travel Creator Program", "https://partner.expediagroup.com/en-us/solutions/explore-our-affiliate-program", false),
            ("travel.agoda", "Agoda", "Agoda Partners", "https://partners.agoda.com/", false),
            ("activities.viator", "Viator", "Viator Affiliate Program", "https://partnerresources.viator.com/travel-content/links/create-links/", false),
            ("activities.getyourguide", "GetYourGuide", "GetYourGuide Partner Program", "https://partner.getyourguide.support/hc/en-us/articles/13981068165917-Our-partner-program", false),
            ("rental.discovercars", "DiscoverCars", "DiscoverCars Affiliate Program", "https://www.discovercars.com/affiliate", false)
        ]
        let admitadNames: [(String, String)] = [
            ("retail.varus", "VARUS"), ("retail.foxtrot", "Foxtrot"), ("retail.answear", "Answear"),
            ("retail.citrus", "Citrus"), ("retail.moyo", "MOYO"), ("retail.telemart", "Telemart"),
            ("retail.intertop", "INTERTOP"), ("retail.masterzoo", "Master Zoo"), ("retail.anc", "ANC"),
            ("retail.agromarket", "Agromarket"), ("retail.vivat", "Vivat"), ("retail.toyhouse", "Будинок іграшок"),
            ("retail.bookye", "Книгарня Є"), ("retail.duna", "Duna"), ("retail.brocard", "Brocard"),
            ("retail.samsungua", "Samsung Ukraine"), ("service.hotlinefinance", "Hotline.Finance"),
            ("activities.pokupon", "Pokupon"), ("events.kontramarka", "Kontramarka"), ("travel.ticketsua", "Tickets.ua")
        ]
        let noProgram: [(String, String)] = [
            ("jobs.dcz", "Державна служба зайнятості"), ("transport.uz", "Укрзалізниця"),
            ("parcel.novaposhta", "Нова пошта"), ("parcel.ukrposhta", "Укрпошта"), ("parcel.meest", "Meest"),
            ("reference.nbu", "National Bank of Ukraine"), ("restaurant.expirenza", "Expirenza"),
            ("restaurant.table", "Table"), ("taxi.uklon", "Uklon"), ("taxi.bolt", "Bolt"),
            ("delivery.glovo", "Glovo"), ("delivery.boltfood", "Bolt Food")
        ]
        let unknown: [(String, String)] = [
            ("market.prom", "Prom.ua"), ("retail.silpo", "Сільпо"), ("retail.fora", "Фора"),
            ("retail.fozzy", "Fozzy"), ("rental.getmancar", "Getmancar"), ("cinema.multiplex", "Multiplex"),
            ("cinema.planetakino", "Планета Кіно"), ("jobs.workua", "Work.ua"), ("jobs.robotaua", "robota.ua"),
            ("jobs.jobsua", "Jobs.ua"), ("jobs.djinni", "Djinni"), ("jobs.dou", "DOU Jobs"),
            ("jobs.happymonday", "Happy Monday"), ("rental.boltdrive", "Bolt Drive"), ("taxi.uber", "Uber"),
        ]
        var output = directReady.map { value in
            make(value.0, value.1, .affiliateReadyOwnerAction, value.2, exact: true,
                 campaign: true, owner: true, click: value.4, evidence: value.3)
        }
        output += admitadNames.map {
            make($0.0, $0.1, .affiliateReadyOwnerAction, "Admitad", exact: true,
                 campaign: true, owner: true, evidence: "https://www.admitad.com/ua/store/")
        }
        output += noProgram.map {
            make($0.0, $0.1, .functionalNoAffiliateProgram, "official functional route only",
                 evidence: "https://www.admitad.com/ua/store/")
        }
        output += unknown.map {
            make($0.0, $0.1, .unknown, "no current official publisher mechanism established",
                 evidence: "https://www.admitad.com/ua/store/")
        }
        output.append(make("lodging.airbnb", "Airbnb", .unsupported,
                           "publisher program closed to applications", evidence: "https://www.airbnb.com/help/article/4236"))
        return output.sorted { $0.id < $1.id }
    }()

    static func policy(for providerID: String) -> CanonicalPartnerPolicy? {
        records.first { $0.providerID == providerID }
    }

    private static func make(_ id: String, _ name: String, _ decision: CanonicalPartnerDecision,
                             _ mechanism: String, exact: Bool = false, campaign: Bool = false,
                             owner: Bool = false, click: Bool = false,
                             evidence: String) -> CanonicalPartnerPolicy {
        .init(id: id, providerID: id, displayName: name, decision: decision,
              networkOrMechanism: mechanism, supportsExactDestination: exact,
              supportsCampaignOrSubID: campaign, requiresOwnerAction: owner,
              costToUniversalAssistant: 0, requiresExplicitUserActivation: click,
              officialEvidence: URL(string: evidence)!, verifiedAt: verifiedAt)
    }
}

enum AffiliateProgramStatus: Int, Codable, CaseIterable, Sendable {
    case candidate, applicationRequired, applied, approved, credentialsReceived
    case implemented, testVerified, productionVerified, earningVerified
}

struct AffiliateProgramEvidence: Codable, Equatable, Sendable {
    let reference: String
    let kind: String
    let recordedAt: Date
    let provesConversionAttribution: Bool
}

struct AffiliateProgramRecord: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let providerID: String
    var status: AffiliateProgramStatus
    var evidence: [AffiliateProgramEvidence]
    var updatedAt: Date
}

enum AffiliateProgramRegistryError: Error, Equatable { case invalidRecord, invalidTransition, earningEvidenceRequired }

actor AffiliateProgramRegistry {
    private let store: LocalStore
    private let filename: String
    private var records: [String: AffiliateProgramRecord] = [:]

    init(store: LocalStore = .shared, filename: String = "affiliate-program-status.json") {
        self.store = store; self.filename = filename
    }

    func restore() async throws {
        records = Dictionary(uniqueKeysWithValues: (try await store.load([AffiliateProgramRecord].self, from: filename) ?? []).map { ($0.id, $0) })
    }

    func register(id: String, providerID: String, now: Date = .now) async throws -> AffiliateProgramRecord {
        guard !id.isEmpty, !providerID.isEmpty else { throw AffiliateProgramRegistryError.invalidRecord }
        if let existing = records[id] { return existing }
        let value = AffiliateProgramRecord(id: id, providerID: providerID, status: .candidate, evidence: [], updatedAt: now)
        records[id] = value; try await persist(); return value
    }

    func transition(id: String, to status: AffiliateProgramStatus, evidence: AffiliateProgramEvidence? = nil, now: Date = .now) async throws -> AffiliateProgramRecord {
        guard var value = records[id] else { throw AffiliateProgramRegistryError.invalidRecord }
        guard status.rawValue == value.status.rawValue + 1 else { throw AffiliateProgramRegistryError.invalidTransition }
        if status == .earningVerified, evidence?.provesConversionAttribution != true { throw AffiliateProgramRegistryError.earningEvidenceRequired }
        if let evidence { value.evidence.append(evidence) }
        value.status = status; value.updatedAt = now; records[id] = value
        try await persist(); return value
    }

    func record(id: String) -> AffiliateProgramRecord? { records[id] }

    private func persist() async throws {
        try await store.save(records.values.sorted { $0.id < $1.id }, as: filename)
    }
}
