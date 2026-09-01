import Foundation

enum AffiliateAttributionState: String, Equatable, Sendable {
    case notConfigured
    case outboundParametersApplied
}

enum PurchaseHandoffState: String, Equatable, Sendable {
    case destinationPrepared
}

struct AffiliateRoutingConfiguration: Equatable, Sendable {
    let providerID: String
    let allowedHosts: Set<String>
    let allowedParameterNames: Set<String>
    let parameterValues: [String: String]
    var allowedAppSchemes: Set<String> = []
    let officiallyVerifiedAt: Date
    var enabled = true
}

struct PurchaseHandoff: Equatable, Sendable {
    let offerID: String
    let destination: URL
    let attribution: AffiliateAttributionState
    let state: PurchaseHandoffState
}

enum AffiliateRoutingError: Error, Equatable, Sendable {
    case invalidExactDestination, providerMismatch, hostNotAllowed, parameterNotAllowed, appSchemeNotAllowed
}

struct AffiliatePurchaseRouter: Sendable {
    func route(_ offer: NormalizedOffer, configuration: AffiliateRoutingConfiguration?) throws -> PurchaseHandoff {
        try validateExactWebURL(offer.exactPurchaseURL)
        guard let configuration, configuration.enabled else {
            return .init(offerID: offer.id, destination: offer.exactPurchaseURL,
                         attribution: .notConfigured, state: .destinationPrepared)
        }
        guard configuration.providerID == offer.providerID else { throw AffiliateRoutingError.providerMismatch }
        guard let host = offer.exactPurchaseURL.host?.lowercased(),
              configuration.allowedHosts.map({ $0.lowercased() }).contains(host) else {
            throw AffiliateRoutingError.hostNotAllowed
        }
        guard Set(configuration.parameterValues.keys).isSubset(of: configuration.allowedParameterNames) else {
            throw AffiliateRoutingError.parameterNotAllowed
        }

        if let appURL = offer.exactAppURL {
            guard let scheme = appURL.scheme?.lowercased(), configuration.allowedAppSchemes.contains(scheme) else {
                throw AffiliateRoutingError.appSchemeNotAllowed
            }
            let destination = try applying(configuration.parameterValues, to: appURL)
            return .init(offerID: offer.id, destination: destination,
                         attribution: configuration.parameterValues.isEmpty ? .notConfigured : .outboundParametersApplied,
                         state: .destinationPrepared)
        }

        let destination = try applying(configuration.parameterValues, to: offer.exactPurchaseURL)
        return .init(offerID: offer.id, destination: destination,
                     attribution: configuration.parameterValues.isEmpty ? .notConfigured : .outboundParametersApplied,
                     state: .destinationPrepared)
    }

    private func applying(_ values: [String: String], to url: URL) throws -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw AffiliateRoutingError.invalidExactDestination
        }
        var query = components.queryItems ?? []
        for key in values.keys.sorted() {
            query.removeAll { $0.name == key }
            query.append(.init(name: key, value: values[key]))
        }
        components.queryItems = query.isEmpty ? nil : query
        guard let destination = components.url else { throw AffiliateRoutingError.invalidExactDestination }
        return destination
    }

    private func validateExactWebURL(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https", url.host != nil,
              !url.path.isEmpty, url.path != "/" else { throw AffiliateRoutingError.invalidExactDestination }
    }
}
