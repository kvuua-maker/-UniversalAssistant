import Foundation

struct FoodDeliveryRequest: Equatable, Sendable {
    let query: String
    let latitude: Double
    let longitude: Double
    let maximumDeliveryMinutes: Int?
}

struct FoodDeliveryOffer: Identifiable, Equatable, Sendable {
    let id: String
    let providerID: String
    let restaurant: String
    let item: Money
    let deliveryFee: Money?
    let serviceFee: Money?
    let otherRequiredFees: Money?
    let deliveryMinutes: Int?
    let availabilityVerified: Bool
    let priceVerified: Bool
    let etaVerified: Bool
    let sourceTimestamp: Date
    let orderURL: URL

    var deliveredTotal: Money? {
        guard priceVerified, let deliveryFee, let serviceFee, let otherRequiredFees,
              let subtotal = item.adding(deliveryFee), let withService = subtotal.adding(serviceFee)
        else { return nil }
        return withService.adding(otherRequiredFees)
    }
}

protocol FoodDeliveryProvider: Sendable {
    var providerID: String { get }
    func search(_ request: FoodDeliveryRequest) async throws -> [FoodDeliveryOffer]
}

struct FoodDeliveryComparison: Equatable, Sendable {
    let comparable: [FoodDeliveryOffer]
    let incomplete: [FoodDeliveryOffer]
    let failures: [String: String]
}

enum FoodDeliveryAction: Equatable, Sendable { case confirmedHandoff(URL), confirmationRequired, unavailable }

struct FoodDeliveryComparisonEngine: Sendable {
    let providers: [any FoodDeliveryProvider]
    let timeout: Duration

    init(providers: [any FoodDeliveryProvider], timeout: Duration = .seconds(5)) {
        self.providers = providers; self.timeout = timeout
    }

    func compare(_ request: FoodDeliveryRequest, now: Date = .now) async -> FoodDeliveryComparison {
        let responses = await withTaskGroup(of: (String, Result<[FoodDeliveryOffer], Error>).self) { group in
            for provider in providers.prefix(6) {
                group.addTask {
                    do {
                        let offers = try await withThrowingTaskGroup(of: [FoodDeliveryOffer].self) { tasks in
                            tasks.addTask { try await provider.search(request) }
                            tasks.addTask { try await Task.sleep(for: timeout); throw CancellationError() }
                            let first = try await tasks.next() ?? []
                            tasks.cancelAll(); return first
                        }
                        return (provider.providerID, .success(offers))
                    }
                    catch { return (provider.providerID, .failure(error)) }
                }
            }
            var result: [(String, Result<[FoodDeliveryOffer], Error>)] = []
            for await value in group { result.append(value) }
            return result
        }
        var valid: [FoodDeliveryOffer] = [], failures: [String: String] = [:]
        for (providerID, response) in responses {
            switch response {
            case .failure: failures[providerID] = "provider_error"
            case .success(let offers):
                valid += offers.filter { $0.providerID == providerID && $0.availabilityVerified &&
                    $0.orderURL.scheme == "https" && now.timeIntervalSince($0.sourceTimestamp) <= 900 }
            }
        }
        let withinDeadline = valid.filter { offer in
            guard let maximum = request.maximumDeliveryMinutes else { return true }
            return offer.etaVerified && (offer.deliveryMinutes.map { $0 <= maximum } ?? false)
        }
        let comparable = withinDeadline.filter { $0.deliveredTotal != nil && $0.etaVerified }
            .sorted { left, right in
                let l = left.deliveredTotal!, r = right.deliveredTotal!
                if l.currency != r.currency { return l.currency < r.currency }
                if l.amount != r.amount { return l.amount < r.amount }
                return (left.deliveryMinutes ?? .max) < (right.deliveryMinutes ?? .max)
            }
        return .init(comparable: comparable,
            incomplete: withinDeadline.filter { $0.deliveredTotal == nil || !$0.etaVerified }.sorted { $0.id < $1.id },
            failures: failures)
    }

    func order(_ offer: FoodDeliveryOffer, confirmed: Bool) -> FoodDeliveryAction {
        guard offer.availabilityVerified, offer.orderURL.scheme == "https" else { return .unavailable }
        return confirmed ? .confirmedHandoff(offer.orderURL) : .confirmationRequired
    }
}
