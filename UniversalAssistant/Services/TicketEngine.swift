import Foundation

enum TicketMode: String, Codable, CaseIterable, Sendable {
    case rail, coach, flight, ferry, event, other
}

struct TicketSegment: Equatable, Sendable {
    let origin: String
    let destination: String
    let departure: Date
    let arrival: Date

    var isValid: Bool {
        !origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && arrival > departure
    }
}

enum TicketInventoryEvidence: Equatable, Sendable {
    case verifiedAvailable(source: String, observedAt: Date)
    case verifiedUnavailable(source: String, observedAt: Date)
    case unknown

    var availability: VerifiedServiceAvailability {
        switch self {
        case .verifiedAvailable: .available
        case .verifiedUnavailable: .unavailable
        case .unknown: .unknown
        }
    }

    var observation: (source: String, date: Date)? {
        switch self {
        case let .verifiedAvailable(source, date), let .verifiedUnavailable(source, date): (source, date)
        case .unknown: nil
        }
    }
}

struct TicketOffer: Identifiable, Equatable, Sendable {
    let id: String
    let providerID: String
    let mode: TicketMode
    let segments: [TicketSegment]
    var fare: Money?
    var inventory: TicketInventoryEvidence
    let fareObservedAt: Date?
    let exactPurchaseURL: URL

    var departure: Date? { segments.first?.departure }
    var arrival: Date? { segments.last?.arrival }
    var transferCount: Int { max(0, segments.count - 1) }

    var hasValidItinerary: Bool {
        guard !segments.isEmpty, segments.allSatisfy(\.isValid) else { return false }
        return zip(segments, segments.dropFirst()).allSatisfy { $0.arrival <= $1.departure }
    }
}

struct TicketSearchRequest: Equatable, Sendable {
    var allowedModes: Set<TicketMode> = Set(TicketMode.allCases)
    var departureNotBefore: Date?
    var arrivalNotAfter: Date?
    var maximumPrice: Money?
    var maximumTransfers: Int?
    var requiresVerifiedInventory = false
    var origin: String?
    var destination: String?
    var maximumDurationSeconds: TimeInterval?
    var providerIDs: Set<String> = []
}

protocol TicketProvider: Sendable {
    var providerID: String { get }
    func search(_ request: TicketSearchRequest) async throws -> [TicketOffer]
}

struct TicketProviderSearchResponse: Sendable {
    let offers: [TicketOffer]
    let failures: [ProviderFailure]
    let coverage: ProviderFanoutCoverage
}

struct TicketProviderCoordinator: Sendable {
    let providers: [any TicketProvider]
    var timeout: Duration = .seconds(5)
    var maximumProviders = 8

    func search(_ request: TicketSearchRequest, now: Date = .now) async throws -> TicketProviderSearchResponse {
        let operations = providers.map { provider in
            ProviderOperation<TicketOffer>(providerID: provider.providerID) { try await provider.search(request) }
        }
        let response = try await ProviderFanoutEngine<TicketOffer>(
            timeout: timeout, maximumProviders: maximumProviders
        ).execute(operations)
        let ranked = (try? TicketEngine().rank(response.values, request: request, now: now)) ?? []
        let coverage: ProviderFanoutCoverage = response.failures.isEmpty ? .complete : (ranked.isEmpty ? .failed : .partial)
        return .init(offers: ranked, failures: response.failures, coverage: coverage)
    }
}

enum TicketEngineError: Error, Equatable, Sendable {
    case invalidRequest, noSupportedModes, noVerifiedOffers, invalidExactDestination
}

struct TicketEngine: Sendable {
    var maximumEvidenceAge: TimeInterval = 10 * 60

    func rank(_ offers: [TicketOffer], request: TicketSearchRequest, now: Date = .now) throws -> [TicketOffer] {
        guard maximumEvidenceAge > 0,
              request.maximumPrice.map({ $0.amount >= 0 }) ?? true,
              request.maximumTransfers.map({ $0 >= 0 }) ?? true,
              request.maximumDurationSeconds.map({ $0 >= 0 }) ?? true else { throw TicketEngineError.invalidRequest }
        guard !request.allowedModes.isEmpty else { throw TicketEngineError.noSupportedModes }

        let candidates = offers.enumerated().filter { _, offer in
            guard request.allowedModes.contains(offer.mode), offer.hasValidItinerary,
                  offer.inventory.availability != .unavailable else { return false }
            if let origin = request.origin?.trimmingCharacters(in: .whitespacesAndNewlines), !origin.isEmpty {
                guard offer.segments.first?.origin.localizedCaseInsensitiveCompare(origin) == .orderedSame else { return false }
            }
            if let destination = request.destination?.trimmingCharacters(in: .whitespacesAndNewlines), !destination.isEmpty {
                guard offer.segments.last?.destination.localizedCaseInsensitiveCompare(destination) == .orderedSame else { return false }
            }
            if !request.providerIDs.isEmpty, !request.providerIDs.contains(offer.providerID) { return false }
            if request.requiresVerifiedInventory {
                guard offer.inventory.availability == .available,
                      let observation = offer.inventory.observation,
                      isFresh(observation.date, now: now),
                      !observation.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            }
            if let earliest = request.departureNotBefore {
                guard let departure = offer.departure, departure >= earliest else { return false }
            }
            if let latest = request.arrivalNotAfter {
                guard let arrival = offer.arrival, arrival <= latest else { return false }
            }
            if let budget = request.maximumPrice {
                guard let fare = offer.fare, fare.currency == budget.currency, fare.amount <= budget.amount,
                      let observed = offer.fareObservedAt, isFresh(observed, now: now) else { return false }
            }
            if let maximum = request.maximumTransfers, offer.transferCount > maximum { return false }
            if let maximum = request.maximumDurationSeconds,
               let departure = offer.departure, let arrival = offer.arrival,
               arrival.timeIntervalSince(departure) > maximum { return false }
            return true
        }
        guard !candidates.isEmpty else { throw TicketEngineError.noVerifiedOffers }
        return candidates.sorted { left, right in
            let leftArrival = left.element.arrival!, rightArrival = right.element.arrival!
            if leftArrival != rightArrival { return leftArrival < rightArrival }
            if left.element.transferCount != right.element.transferCount {
                return left.element.transferCount < right.element.transferCount
            }
            return left.offset < right.offset
        }.map(\.element)
    }

    func purchaseHandoff(for offer: TicketOffer, now: Date = .now) throws -> TicketPurchaseHandoff {
        guard offer.hasValidItinerary, offer.inventory.availability == .available,
              let observation = offer.inventory.observation, isFresh(observation.date, now: now),
              !observation.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              offer.exactPurchaseURL.scheme?.lowercased() == "https",
              offer.exactPurchaseURL.host != nil, !offer.exactPurchaseURL.path.isEmpty,
              offer.exactPurchaseURL.path != "/" else { throw TicketEngineError.invalidExactDestination }
        return .init(offerID: offer.id, destination: offer.exactPurchaseURL, state: .destinationPrepared)
    }

    private func isFresh(_ date: Date, now: Date) -> Bool {
        let age = now.timeIntervalSince(date)
        return age >= -60 && age <= maximumEvidenceAge
    }
}

enum TicketPurchaseState: String, Equatable, Sendable { case destinationPrepared }

struct TicketPurchaseHandoff: Equatable, Sendable {
    let offerID: String
    let destination: URL
    let state: TicketPurchaseState
}
