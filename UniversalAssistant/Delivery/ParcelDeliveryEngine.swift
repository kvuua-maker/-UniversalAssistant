import Foundation

enum ParcelCarrier: String, Codable, Sendable { case novaPoshta, ukrposhta, meest, other }
enum ParcelStatusKnowledge: String, Codable, Sendable { case confirmedEvent, providerEstimate, unknown }

struct ParcelEvent: Codable, Equatable, Sendable {
    let code: String
    let description: String
    let occurredAt: Date?
    let location: String?
}

struct ParcelTrackingResult: Equatable, Sendable {
    let carrier: ParcelCarrier
    let trackingNumber: String
    let status: String?
    let estimatedDelivery: Date?
    let knowledge: ParcelStatusKnowledge
    let events: [ParcelEvent]
    let observedAt: Date
    let sourceReference: String
}

struct ParcelBranch: Identifiable, Equatable, Sendable {
    let id: String
    let carrier: ParcelCarrier
    let name: String
    let latitude: Double
    let longitude: Double
    let sourceReference: String
}

protocol ParcelDeliveryProvider: Sendable {
    var carrier: ParcelCarrier { get }
    func track(_ number: String) async throws -> ParcelTrackingResult
    func branches(near latitude: Double, longitude: Double) async throws -> [ParcelBranch]
}

struct ParcelLookupReport: Equatable, Sendable {
    let results: [ParcelTrackingResult]
    let failures: [ParcelCarrier: String]
    var isPartial: Bool { !results.isEmpty && !failures.isEmpty }
}

enum ParcelDeliveryError: Error, Equatable { case invalidTrackingNumber, noVerifiedResult }

struct ParcelDeliveryEngine: Sendable {
    let providers: [any ParcelDeliveryProvider]

    func track(number raw: String, preferredCarrier: ParcelCarrier? = nil) async throws -> ParcelLookupReport {
        let number = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard number.count >= 5, number.count <= 40,
              number.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            throw ParcelDeliveryError.invalidTrackingNumber
        }
        let selected = preferredCarrier.map { carrier in providers.filter { $0.carrier == carrier } } ?? providers
        let responses = await withTaskGroup(of: (ParcelCarrier, Result<ParcelTrackingResult, Error>).self) { group in
            for provider in selected {
                group.addTask {
                    do { return (provider.carrier, .success(try await provider.track(number))) }
                    catch { return (provider.carrier, .failure(error)) }
                }
            }
            var values: [(ParcelCarrier, Result<ParcelTrackingResult, Error>)] = []
            for await value in group { values.append(value) }
            return values
        }
        var results: [ParcelTrackingResult] = [], failures: [ParcelCarrier: String] = [:]
        for (carrier, response) in responses {
            switch response {
            case let .success(value): results.append(value)
            case let .failure(error): failures[carrier] = String(describing: error)
            }
        }
        guard !results.isEmpty || !failures.isEmpty else { throw ParcelDeliveryError.noVerifiedResult }
        return .init(results: results.sorted { $0.carrier.rawValue < $1.carrier.rawValue }, failures: failures)
    }

    func navigationURL(for branch: ParcelBranch) -> URL? {
        URL(string: "https://maps.apple.com/?daddr=\(branch.latitude),\(branch.longitude)")
    }
}
