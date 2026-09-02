import Foundation
import Testing
@testable import UniversalAssistant

private actor ProviderProbe {
    var calls = 0
    func called() { calls += 1 }
}

private struct SearchProviderStub: RetailProvider {
    let providerID: String
    let probe: ProviderProbe
    var delay: Duration = .zero
    var fails = false

    func search(_ request: RetailSearchRequest) async throws -> [NormalizedOffer] {
        await probe.called()
        try await Task.sleep(for: delay)
        if fails { throw RetailProviderError.unavailable }
        return [searchOffer(provider: providerID)]
    }
}

private func searchRequest(model: String = "Model") -> RetailSearchRequest {
    .init(identity: .init(brand: "Brand", model: model, productType: "phone", sku: "SKU-\(model)", gtin: nil,
                          variant: .init(color: "black", condition: .new)))
}

private func searchOffer(provider: String, sourceTimestamp: Date = .now) -> NormalizedOffer {
    let zero = CostComponent(value: Money(amount: 0, currency: "UAH"), knowledge: .known)
    let identity = searchRequest().identity
    return .init(id: provider, providerID: provider, providerOfferID: "offer", identity: identity,
                 identityMatch: .init(level: .exact, evidence: ["sku"], conflicts: []),
                 seller: .init(id: provider, name: provider), availability: .inStock,
                 cost: .init(item: .init(amount: 1000, currency: "UAH"), shipping: zero, tax: zero, duties: zero, requiredOther: zero),
                 deliversToUkraine: true, exactPurchaseURL: URL(string: "https://example.com/\(provider)")!,
                 sourceTimestamp: sourceTimestamp, fetchedAt: .now, affiliateAttributionSupported: false)
}

@Suite("Commerce search pipeline") struct CommerceSearchEngineTests {
    @Test func identicalConcurrentRequestsShareOneProviderCall() async throws {
        let probe = ProviderProbe()
        let engine = CommerceSearchEngine(providers: [SearchProviderStub(providerID: "one", probe: probe, delay: .milliseconds(30))])
        async let first = engine.search(searchRequest())
        async let second = engine.search(searchRequest())
        _ = try await (first, second)
        #expect(await probe.calls == 1)
    }

    @Test func freshCacheIsReusedAndExpiresTruthfully() async throws {
        let probe = ProviderProbe()
        let engine = CommerceSearchEngine(providers: [SearchProviderStub(providerID: "one", probe: probe)], cacheTTL: 10)
        let now = Date()
        _ = try await engine.search(searchRequest(), now: now)
        let cached = try await engine.search(searchRequest(), now: now.addingTimeInterval(5))
        #expect(cached.isFromCache)
        _ = try await engine.search(searchRequest(), now: now.addingTimeInterval(11))
        #expect(await probe.calls == 2)
    }

    @Test func memoryPressureCancelsWorkAndPurgesCachedResults() async throws {
        let probe = ProviderProbe()
        let engine = CommerceSearchEngine(providers: [SearchProviderStub(providerID: "one", probe: probe)], cacheTTL: 60)
        let now = Date()
        _ = try await engine.search(searchRequest(), now: now)
        await engine.handleMemoryPressure()
        let refreshed = try await engine.search(searchRequest(), now: now.addingTimeInterval(1))
        #expect(!refreshed.isFromCache)
        #expect(await probe.calls == 2)
    }

    @Test func providerFanoutIsBounded() async throws {
        let probes = (0..<8).map { _ in ProviderProbe() }
        let providers = probes.enumerated().map { SearchProviderStub(providerID: "p\($0.offset)", probe: $0.element) }
        let result = try await CommerceSearchEngine(providers: providers, maximumProviders: 3).search(searchRequest())
        #expect(result.offers.count == 3)
        var calls = 0
        for probe in probes { calls += await probe.calls }
        #expect(calls == 3)
    }

    @Test func timeoutAndFailureReturnVerifiedPartialResults() async throws {
        let fast = SearchProviderStub(providerID: "fast", probe: ProviderProbe())
        let slow = SearchProviderStub(providerID: "slow", probe: ProviderProbe(), delay: .seconds(1))
        let broken = SearchProviderStub(providerID: "broken", probe: ProviderProbe(), fails: true)
        let result = try await CommerceSearchEngine(providers: [fast, slow, broken], timeout: .milliseconds(10)).search(searchRequest())
        #expect(result.offers.map(\.providerID) == ["fast"])
        #expect(result.failures.map(\.providerID) == ["broken", "slow"])
        #expect(result.failures.contains { $0.reason == "timeout" })
    }

    @Test func progressiveSearchFinishesWithStableAggregate() async throws {
        let engine = CommerceSearchEngine(providers: [
            SearchProviderStub(providerID: "a", probe: ProviderProbe()),
            SearchProviderStub(providerID: "b", probe: ProviderProbe(), delay: .milliseconds(5))
        ])
        let stream = try await engine.progressiveSearch(searchRequest())
        var final: CommerceSearchUpdate?
        for await update in stream where update.isComplete { final = update }
        #expect(final?.response.offers.count == 2)
    }

    @Test func staleOfferIsNeverReturnedAsCurrent() async throws {
        struct StaleProvider: RetailProvider {
            let providerID = "stale"
            func search(_ request: RetailSearchRequest) async throws -> [NormalizedOffer] {
                [searchOffer(provider: providerID, sourceTimestamp: .now.addingTimeInterval(-3600))]
            }
        }
        let result = try await CommerceSearchEngine(providers: [StaleProvider()]).search(searchRequest())
        #expect(result.offers.isEmpty)
    }
}
