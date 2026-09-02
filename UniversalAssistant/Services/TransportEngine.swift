import Foundation

enum TransportMode: String, Codable, CaseIterable, Sendable {
    case taxi, publicTransit, walking, driving, train, intercityBus, air, multimodal
}

enum TransportSegmentKind: String, Codable, Sendable { case walking, transit, transfer }

struct TransportSegment: Equatable, Codable, Sendable {
    let kind: TransportSegmentKind
    var routeName: String?
    var originStop: String?
    var destinationStop: String?
    var departure: Date?
    var arrival: Date?
    var durationSeconds: TimeInterval?

    var isValid: Bool {
        guard durationSeconds.map({ $0 >= 0 }) ?? true else { return false }
        if let departure, let arrival, arrival < departure { return false }
        if kind == .transit {
            return routeName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
                originStop?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
                destinationStop?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        return true
    }
}

enum TransportEvidenceKind: String, Codable, Sendable {
    case estimated, scheduled, realTime
}

struct TransportEvidence: Equatable, Sendable {
    let source: String
    let kind: TransportEvidenceKind
    let observedAt: Date

    var canProveLiveAvailability: Bool { kind == .realTime }
}

struct TransportOption: Identifiable, Equatable, Sendable {
    let id: String
    let providerID: String
    let mode: TransportMode
    var departure: Date?
    var arrival: Date?
    var durationSeconds: TimeInterval?
    var price: Money?
    var transfers: Int?
    var availability: VerifiedServiceAvailability
    let evidence: TransportEvidence
    var exactHandoffURL: URL?
    var segments: [TransportSegment] = []

    func isFresh(now: Date, maximumAge: TimeInterval) -> Bool {
        let age = now.timeIntervalSince(evidence.observedAt)
        return age >= -60 && age <= maximumAge
    }

    var hasValidTiming: Bool {
        guard durationSeconds.map({ $0 >= 0 }) ?? true,
              transfers.map({ $0 >= 0 }) ?? true else { return false }
        if let departure, let arrival { return arrival >= departure }
        return segments.allSatisfy(\.isValid)
    }
}

struct TransportRequest: Equatable, Sendable {
    var allowedModes: Set<TransportMode> = Set(TransportMode.allCases)
    var departureNotBefore: Date?
    var arrivalNotAfter: Date?
    var maximumDurationSeconds: TimeInterval?
    var maximumPrice: Money?
    var maximumTransfers: Int?
    var requiresVerifiedAvailability = false
}

enum TransportEngineError: Error, Equatable, Sendable {
    case invalidRequest, noSupportedModes, noVerifiedOptions
}

struct TransportEngine: Sendable {
    var maximumEvidenceAge: TimeInterval = 5 * 60

    func rank(_ options: [TransportOption], request: TransportRequest, now: Date = .now) throws -> [TransportOption] {
        guard maximumEvidenceAge > 0,
              request.maximumDurationSeconds.map({ $0 >= 0 }) ?? true,
              request.maximumPrice.map({ $0.amount >= 0 }) ?? true,
              request.maximumTransfers.map({ $0 >= 0 }) ?? true else {
            throw TransportEngineError.invalidRequest
        }
        guard !request.allowedModes.isEmpty else { throw TransportEngineError.noSupportedModes }

        let candidates = options.enumerated().filter { _, option in
            guard request.allowedModes.contains(option.mode), option.hasValidTiming,
                  option.isFresh(now: now, maximumAge: maximumEvidenceAge) else { return false }
            if request.requiresVerifiedAvailability {
                guard option.availability == .available, option.evidence.canProveLiveAvailability else { return false }
            } else if option.availability == .unavailable { return false }
            if let earliest = request.departureNotBefore {
                guard let departure = option.departure, departure >= earliest else { return false }
            }
            if let latest = request.arrivalNotAfter {
                guard let arrival = option.arrival, arrival <= latest else { return false }
            }
            if let maximum = request.maximumDurationSeconds {
                guard let duration = option.durationSeconds, duration <= maximum else { return false }
            }
            if let budget = request.maximumPrice {
                guard let price = option.price, price.currency == budget.currency, price.amount <= budget.amount else { return false }
            }
            if let maximum = request.maximumTransfers {
                guard let transfers = option.transfers, transfers <= maximum else { return false }
            }
            return true
        }
        guard !candidates.isEmpty else { throw TransportEngineError.noVerifiedOptions }

        return candidates.sorted { left, right in
            let comparison = compare(left.element, right.element)
            return comparison == .orderedSame ? left.offset < right.offset : comparison == .orderedAscending
        }.map(\.element)
    }

    func option(from ride: RideOffer, source: String) -> TransportOption? {
        guard let timestamp = ride.evidenceTimestamp,
              !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return .init(
            id: ride.id, providerID: ride.providerID, mode: .taxi,
            departure: timestamp.addingTimeInterval(ride.pickupWaitSeconds ?? 0),
            arrival: ride.estimatedArrival,
            durationSeconds: ride.estimatedArrival.map { $0.timeIntervalSince(timestamp) },
            price: ride.price, transfers: 0, availability: ride.availability,
            evidence: .init(source: source, kind: .realTime, observedAt: timestamp),
            exactHandoffURL: ride.exactHandoffURL
        )
    }

    private func compare(_ lhs: TransportOption, _ rhs: TransportOption) -> ComparisonResult {
        if let result = compareOptional(lhs.arrival, rhs.arrival), result != .orderedSame { return result }
        if let result = compareOptional(lhs.durationSeconds, rhs.durationSeconds), result != .orderedSame { return result }
        guard let leftPrice = lhs.price, let rightPrice = rhs.price,
              leftPrice.currency == rightPrice.currency else { return .orderedSame }
        return compareOptional(leftPrice.amount, rightPrice.amount) ?? .orderedSame
    }

    private func compareOptional<T: Comparable>(_ lhs: T?, _ rhs: T?) -> ComparisonResult? {
        switch (lhs, rhs) {
        case let (left?, right?): left == right ? .orderedSame : (left < right ? .orderedAscending : .orderedDescending)
        case (_?, nil): .orderedAscending
        case (nil, _?): .orderedDescending
        case (nil, nil): nil
        }
    }
}
