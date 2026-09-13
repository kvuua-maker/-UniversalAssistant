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
    var requestSubIDParameterName: String? = nil
    var redirect: AffiliateRedirectConfiguration? = nil
    var requiresExplicitUserActivation = false
}

struct AffiliateRedirectConfiguration: Equatable, Sendable {
    let baseURL: URL
    let destinationParameterName: String
}

struct PurchaseHandoff: Equatable, Sendable {
    let offerID: String
    let destination: URL
    let attribution: AffiliateAttributionState
    let state: PurchaseHandoffState
    var requiresExplicitUserActivation = false
}

enum AffiliateRoutingError: Error, Equatable, Sendable {
    case invalidExactDestination, providerMismatch, hostNotAllowed, parameterNotAllowed, appSchemeNotAllowed
    case invalidRedirect
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

    func route(
        providerID: String,
        exactDestination: URL,
        configuration: AffiliateRoutingConfiguration?,
        requestID: UUID
    ) throws -> PurchaseHandoff {
        try validateOfficialProviderURL(exactDestination)
        guard let configuration, configuration.enabled else {
            return .init(offerID: requestID.uuidString, destination: exactDestination,
                         attribution: .notConfigured, state: .destinationPrepared)
        }
        guard configuration.providerID == providerID else { throw AffiliateRoutingError.providerMismatch }
        guard let host = exactDestination.host?.lowercased(),
              configuration.allowedHosts.map({ $0.lowercased() }).contains(host) else {
            throw AffiliateRoutingError.hostNotAllowed
        }
        var parameters = configuration.parameterValues
        if let subID = configuration.requestSubIDParameterName {
            guard configuration.allowedParameterNames.contains(subID) else {
                throw AffiliateRoutingError.parameterNotAllowed
            }
            parameters[subID] = requestID.uuidString.lowercased()
        }
        guard Set(parameters.keys).isSubset(of: configuration.allowedParameterNames) else {
            throw AffiliateRoutingError.parameterNotAllowed
        }
        let destination: URL
        if let redirect = configuration.redirect {
            guard redirect.baseURL.scheme?.lowercased() == "https",
                  redirect.baseURL.host != nil,
                  !redirect.destinationParameterName.isEmpty,
                  configuration.allowedParameterNames.contains(redirect.destinationParameterName) else {
                throw AffiliateRoutingError.invalidRedirect
            }
            var wrapped = parameters
            wrapped[redirect.destinationParameterName] = exactDestination.absoluteString
            destination = try applying(wrapped, to: redirect.baseURL)
        } else {
            destination = try applying(parameters, to: exactDestination)
        }
        return .init(
            offerID: requestID.uuidString,
            destination: destination,
            attribution: parameters.isEmpty ? .notConfigured : .outboundParametersApplied,
            state: .destinationPrepared,
            requiresExplicitUserActivation: configuration.requiresExplicitUserActivation
        )
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

    private func validateOfficialProviderURL(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https", url.host != nil else {
            throw AffiliateRoutingError.invalidExactDestination
        }
    }

    private func validateExactWebURL(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https", url.host != nil,
              !url.path.isEmpty, url.path != "/" else { throw AffiliateRoutingError.invalidExactDestination }
    }
}
