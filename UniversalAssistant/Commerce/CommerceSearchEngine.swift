import Foundation

struct CommerceProviderFailure: Equatable, Sendable {
    let providerID: String
    let reason: String
}

struct CommerceSearchResponse: Equatable, Sendable {
    let offers: [NormalizedOffer]
    let failures: [CommerceProviderFailure]
    let isFromCache: Bool
}

struct CommerceSearchUpdate: Equatable, Sendable {
    let response: CommerceSearchResponse
    let isComplete: Bool
}

actor CommerceSearchEngine {
    private struct CacheEntry: Sendable {
        let response: CommerceSearchResponse
        let storedAt: Date
        var lastAccess: Date
    }

    private let providers: [any RetailProvider]
    private let timeout: Duration
    private let cacheTTL: TimeInterval
    private let maximumCacheEntries: Int
    private var cache: [String: CacheEntry] = [:]
    private var inFlight: [String: Task<CommerceSearchResponse, Error>] = [:]

    init(providers: [any RetailProvider], maximumProviders: Int = 6, timeout: Duration = .seconds(5),
         cacheTTL: TimeInterval = 5 * 60, maximumCacheEntries: Int = 32) {
        self.providers = Array(providers.prefix(max(1, maximumProviders)))
        self.timeout = timeout
        self.cacheTTL = max(0, cacheTTL)
        self.maximumCacheEntries = max(1, maximumCacheEntries)
    }

    func search(_ input: RetailSearchRequest, now: Date = .now) async throws -> CommerceSearchResponse {
        let request = try input.validated()
        let key = Self.key(for: request)
        if var entry = cache[key], now.timeIntervalSince(entry.storedAt) <= cacheTTL {
            entry.lastAccess = now; cache[key] = entry
            return .init(offers: entry.response.offers, failures: entry.response.failures, isFromCache: true)
        }
        cache[key] = nil
        if let task = inFlight[key] { return try await task.value }

        let providers = self.providers, timeout = self.timeout
        let task = Task { try await Self.fetchAll(providers, request: request, timeout: timeout, now: now) }
        inFlight[key] = task
        do {
            let response = try await task.value
            inFlight[key] = nil
            cache[key] = .init(response: response, storedAt: now, lastAccess: now)
            trimCache()
            return response
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    func progressiveSearch(_ input: RetailSearchRequest) throws -> AsyncStream<CommerceSearchUpdate> {
        let request = try input.validated()
        let providers = self.providers, timeout = self.timeout
        return AsyncStream { continuation in
            let task = Task {
                var offers: [NormalizedOffer] = [], failures: [CommerceProviderFailure] = []
                await withTaskGroup(of: ProviderResult.self) { group in
                    for provider in providers {
                        group.addTask { await Self.fetch(provider, request: request, timeout: timeout, now: .now) }
                    }
                    for await result in group {
                        switch result {
                        case .success(_, let values): offers.append(contentsOf: values)
                        case .failure(let providerID, let reason): failures.append(.init(providerID: providerID, reason: reason))
                        }
                        let normalized = Self.finalize(offers, failures: failures)
                        continuation.yield(.init(response: normalized, isComplete: false))
                    }
                }
                continuation.yield(.init(response: Self.finalize(offers, failures: failures), isComplete: true))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func cancelAll() {
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
    }

    func handleMemoryPressure() {
        cancelAll()
        cache.removeAll(keepingCapacity: false)
    }

    private func trimCache() {
        while cache.count > maximumCacheEntries, let oldest = cache.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key {
            cache[oldest] = nil
        }
    }

    private static func fetchAll(_ providers: [any RetailProvider], request: RetailSearchRequest,
                                 timeout: Duration, now: Date) async throws -> CommerceSearchResponse {
        try Task.checkCancellation()
        var offers: [NormalizedOffer] = [], failures: [CommerceProviderFailure] = []
        await withTaskGroup(of: ProviderResult.self) { group in
            for provider in providers { group.addTask { await fetch(provider, request: request, timeout: timeout, now: now) } }
            for await result in group {
                switch result {
                case .success(_, let values): offers.append(contentsOf: values)
                case .failure(let providerID, let reason): failures.append(.init(providerID: providerID, reason: reason))
                }
            }
        }
        try Task.checkCancellation()
        return finalize(offers, failures: failures)
    }

    private static func fetch(_ provider: any RetailProvider, request: RetailSearchRequest,
                              timeout: Duration, now: Date) async -> ProviderResult {
        do {
            let values = try await withThrowingTaskGroup(of: [NormalizedOffer].self) { group in
                group.addTask { try await provider.search(request) }
                group.addTask { try await Task.sleep(for: timeout); throw PipelineError.timeout }
                guard let first = try await group.next() else { throw PipelineError.empty }
                group.cancelAll(); return first
            }
            return .success(provider.providerID, values.filter { valid($0, providerID: provider.providerID, now: now) })
        } catch is CancellationError { return .failure(provider.providerID, "cancelled") }
        catch PipelineError.timeout { return .failure(provider.providerID, "timeout") }
        catch { return .failure(provider.providerID, "provider_error") }
    }

    private static func valid(_ offer: NormalizedOffer, providerID: String, now: Date) -> Bool {
        offer.providerID == providerID && offer.identityMatch.level != .unrelated
            && offer.cost.item.amount >= 0 && !offer.cost.item.currency.isEmpty
            && offer.exactPurchaseURL.scheme?.lowercased() == "https"
            && offer.isFresh(now: now)
    }

    private static func finalize(_ offers: [NormalizedOffer], failures: [CommerceProviderFailure]) -> CommerceSearchResponse {
        .init(offers: OfferRanker().rank(OfferDeduplicator().deduplicate(offers)),
              failures: failures.sorted { $0.providerID < $1.providerID }, isFromCache: false)
    }

    private static func key(for request: RetailSearchRequest) -> String {
        let identity = request.identity
        let location = request.location.map { "\($0.latitude),\($0.longitude),\($0.radiusMeters)" }
        return [request.region.uppercased(), String(request.limit), request.fulfillment.rawValue,
                request.priceRange?.minimum.map { "\($0.amount):\($0.currency)" },
                request.priceRange?.maximum.map { "\($0.amount):\($0.currency)" }, location,
                identity.gtin, identity.sku, identity.brand,
                identity.model, identity.productType, identity.variant.storage, identity.variant.size,
                identity.variant.color, identity.variant.configuration].map { $0 ?? "" }.joined(separator: "|").lowercased()
    }
}

private enum PipelineError: Error { case timeout, empty }
private enum ProviderResult: Sendable {
    case success(String, [NormalizedOffer])
    case failure(String, String)
}
