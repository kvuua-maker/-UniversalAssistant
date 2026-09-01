import Foundation

enum FashionAudience: String, Codable, Sendable { case women, men, kids, unisex, unspecified }
enum FashionCategory: String, Codable, Sendable { case footwear, clothing, accessories, unspecified }
enum FashionChannel: String, Codable, Sendable { case online, nearby, either }
enum FashionCollectionClaim: String, Codable, Sendable { case latestCollection, newArrival, discount }

struct FashionDiscoveryRequest: Equatable, Sendable {
    let audience: FashionAudience
    let category: FashionCategory
    var brand: String?
    var size: String?
    var color: String?
    var season: String?
    var maximumPrice: Money?
    var channel: FashionChannel = .either
    var requestedClaims: Set<FashionCollectionClaim> = []

    init(command: StructuredCommand) throws {
        guard [.fashionDiscovery, .show, .productSearch].contains(command.intent) else {
            throw FashionDiscoveryError.unsupportedIntent
        }
        audience = Self.audience(in: command.normalizedText)
        category = FashionCategory(rawValue: command.constraints.category ?? "") ?? .unspecified
        brand = command.constraints.brand
        size = command.constraints.size
        color = command.constraints.color
        season = command.constraints.season
        if let amount = command.constraints.maximumPrice, let currency = command.constraints.currency {
            maximumPrice = .init(amount: amount, currency: currency)
        }
        let text = command.normalizedText
        let localizedNewCollection = (text.contains("нов") && text.contains("колек"))
            || text.contains("neue kollektion") || text.contains("nouvelle collection")
        if text.contains("latest") || localizedNewCollection {
            requestedClaims.insert(.latestCollection)
        }
        if ["new arrival", "новинк", "neu eingetroffen", "nouveauté"].contains(where: text.contains) {
            requestedClaims.insert(.newArrival)
        }
        if ["discount", "зниж", "скид", "rabatt", "remise"].contains(where: text.contains) {
            requestedClaims.insert(.discount)
        }
    }

    private static func audience(in text: String) -> FashionAudience {
        if ["жіноч", "женск", "women", "damen", "femme"].contains(where: text.contains) { return .women }
        if ["чоловіч", "мужск", "men", "herren", "homme"].contains(where: text.contains) { return .men }
        if ["дитяч", "детск", "kids", "kinder", "enfant"].contains(where: text.contains) { return .kids }
        if text.contains("unisex") { return .unisex }
        return .unspecified
    }
}

struct FashionSourceResult: Identifiable, Equatable, Sendable {
    let id: String
    let providerID: String
    let title: String
    let officialWebURL: URL
    var officialAppURL: URL?
    let verifiedAt: Date
    var sourceClaims: Set<FashionCollectionClaim> = []
}

struct OfficialFashionSourceConfiguration: Equatable, Sendable {
    let providerID: String
    let allowedHosts: Set<String>
    var allowedAppSchemes: Set<String> = []
}

enum FashionDiscoveryError: Error, Equatable, Sendable {
    case unsupportedIntent
    case unverifiedClaim
    case invalidOfficialDestination
    case providerMismatch
    case hostNotAllowed
    case appSchemeNotAllowed
}

struct FashionOfficialSourceRouter: Sendable {
    func destination(
        for result: FashionSourceResult,
        request: FashionDiscoveryRequest,
        configuration: OfficialFashionSourceConfiguration
    ) throws -> URL {
        guard result.providerID == configuration.providerID else { throw FashionDiscoveryError.providerMismatch }
        guard request.requestedClaims.isSubset(of: result.sourceClaims) else { throw FashionDiscoveryError.unverifiedClaim }

        if let appURL = result.officialAppURL {
            guard let scheme = appURL.scheme?.lowercased(), configuration.allowedAppSchemes.contains(scheme),
                  hasExactPath(appURL) else { throw FashionDiscoveryError.appSchemeNotAllowed }
            return appURL
        }
        guard result.officialWebURL.scheme?.lowercased() == "https",
              let host = result.officialWebURL.host?.lowercased(),
              configuration.allowedHosts.map({ $0.lowercased() }).contains(host),
              hasExactPath(result.officialWebURL) else { throw FashionDiscoveryError.invalidOfficialDestination }
        return result.officialWebURL
    }

    private func hasExactPath(_ url: URL) -> Bool { !url.path.isEmpty && url.path != "/" }
}
