import Foundation
import Testing
@testable import UniversalAssistant

private struct WebDiscoveryFake: RetailWebDiscovery {
    let urls: [URL]
    func productPageURLs(for request: RetailSearchRequest) async throws -> [URL] { urls }
}
private struct PageRetrieverFake: RetailPageRetrieving {
    let responses: [URL: RetailPageResponse]
    func retrieve(_ url: URL) async throws -> RetailPageResponse {
        guard let response = responses[url] else { throw RetailPageFailure.unavailable }
        return response
    }
}
private actor DiscoveryTransportFake: RetailDiscoveryTransport {
    private(set) var request: URLRequest?
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        self.request = request
        let body = #"{"results":[{"url":"https://new-shop.example/p/1"},{"url":"https://new-shop.example/p/1"},{"url":"http://unsafe.example/p/2"}]}"#
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

@Suite("Generic retail web discovery and extraction") struct GenericRetailWebProviderTests {
    private let now = Date(timeIntervalSince1970: 1_788_220_800)
    private func page(_ body: String, url: String = "https://unknown-shop.example/p/boot",
                      source: Date? = nil, fetched: Date? = nil) -> RetailPageResponse {
        .init(finalURL: URL(string: url)!, html: body, fetchedAt: fetched ?? now, sourceTimestamp: source)
    }
    private func jsonLD(name: String = "Boot", sku: String = "SKU-1", price: String = "100",
                        availability: String? = "InStock", size: String? = nil,
                        modified: String? = nil) -> String {
        var fields = [
            #""@context":"https://schema.org""#, #""@type":"Product""#,
            #""name":"\#(name)""#, #""brand":{"@type":"Brand","name":"Acme"}"#,
            #""sku":"\#(sku)""#, #""color":"black""#
        ]
        if let size { fields.append(#""size":"\#(size)""#) }
        if let modified { fields.append(#""dateModified":"\#(modified)""#) }
        var offer = [#""@type":"Offer""#, #""price":"\#(price)""#, #""priceCurrency":"UAH""#]
        if let availability { offer.append(#""availability":"https://schema.org/\#(availability)""#) }
        fields.append(#""offers":{\#(offer.joined(separator: ","))}"#)
        return #"<html><script type="application/ld+json">{\#(fields.joined(separator: ","))}</script></html>"#
    }
    private func request() -> RetailSearchRequest {
        .init(identity: .init(brand: "Acme", model: nil, productType: "Boot",
                              variant: .init(color: "black")))
    }

    @Test func configuredDiscoveryFindsUnknownDomainsWithoutHardcodedRetailers() async throws {
        let transport = DiscoveryTransportFake()
        let discovery = ConfiguredRetailWebDiscovery(endpoint: URL(string: "https://search.example/v1/web")!,
                                                      bearerToken: "runtime-secret", transport: transport)
        let urls = try await discovery.productPageURLs(for: request())
        #expect(urls.map(\.host) == ["new-shop.example"])
        let sent = await transport.request
        #expect(sent?.url?.query?.contains("type=product") == true)
        #expect(sent?.value(forHTTPHeaderField: "Authorization") == "Bearer runtime-secret")
    }

    @Test func unknownRetailerJSONLDReachesNormalizedNativeCardAndTruthfulHandoff() async throws {
        let url = URL(string: "https://unknown-shop.example/p/boot")!
        let provider = GenericRetailWebProvider(discovery: WebDiscoveryFake(urls: [url]),
            retriever: PageRetrieverFake(responses: [url: page(jsonLD())]))
        let offers = try await provider.search(request())
        let offer = try #require(offers.first)
        #expect(offer.providerID == "generic-retail-web")
        #expect(offer.cost.item == Money(amount: 100, currency: "UAH"))
        #expect(offer.availability == .inStock)
        #expect(!offer.affiliateAttributionSupported)
        #expect(CommerceOfferPresentation.make(from: offers).first?.title == "Acme")
        #expect(try AffiliatePurchaseRouter().route(offer, configuration: nil).attribution == .notConfigured)
    }

    @Test func variantsStaySeparateAndUnknownStockStaysUnknown() throws {
        let html = jsonLD(sku: "S-42", size: "42") + jsonLD(sku: "S-43", availability: nil, size: "43")
        let products = try RetailStructuredDataExtractor().extract(page(html))
        #expect(Set(products.compactMap(\.size)) == ["42", "43"])
        #expect(products.first(where: { $0.size == "43" })?.availability == .unknown)
    }

    @Test func currentPagePriceAndOutOfStockReplaceOldEvidenceWithoutInference() throws {
        let extractor = RetailStructuredDataExtractor()
        #expect(try extractor.extract(page(jsonLD(price: "120"))).first?.price?.amount == 120)
        let changed = try extractor.extract(page(jsonLD(price: "95", availability: "OutOfStock")))
        #expect(changed.first?.price?.amount == 95)
        #expect(changed.first?.availability == .outOfStock)
    }

    @Test func staleStructuredEvidenceIsNotReturnedAsLiveOffer() async throws {
        let url = URL(string: "https://unknown-shop.example/p/boot")!
        let stale = page(jsonLD(modified: "2026-08-01T00:00:00Z"), fetched: now)
        let provider = GenericRetailWebProvider(discovery: WebDiscoveryFake(urls: [url]),
            retriever: PageRetrieverFake(responses: [url: stale]))
        #expect(try await provider.search(request()).isEmpty)
    }

    @Test(arguments: [
        ("<html>captcha verify you are human</html>", RetailPageFailure.captcha),
        ("<html>login required</html>", .loginRequired),
        ("<html>request blocked</html>", .blocked),
        ("<html><script>renderProduct()</script></html>", .dynamicPage),
        ("<html><script type=\"application/ld+json\">{bad}</script></html>", .malformed)
    ]) func unavailablePagesRemainFailuresNotNoProduct(_ html: String, _ expected: RetailPageFailure) {
        #expect(throws: expected) { try RetailStructuredDataExtractor().extract(page(html)) }
    }

    @Test func unavailableSearchResultPageProducesNoFabricatedOffer() async throws {
        let url = URL(string: "https://unknown-shop.example/p/missing")!
        let provider = GenericRetailWebProvider(discovery: WebDiscoveryFake(urls: [url]),
            retriever: PageRetrieverFake(responses: [:]))
        await #expect(throws: RetailPageFailure.unavailable) { try await provider.search(request()) }
    }

    @Test func unsafeOrHomepageDiscoveryDestinationsAreRejectedBeforeRetrieval() async throws {
        let urls = [URL(string: "http://shop.example/p/1")!, URL(string: "https://localhost/p/1")!,
                    URL(string: "https://shop.example/")!]
        let provider = GenericRetailWebProvider(discovery: WebDiscoveryFake(urls: urls),
            retriever: PageRetrieverFake(responses: [:]))
        #expect(try await provider.search(request()).isEmpty)
    }

    @Test func openGraphFallbackHasLowerBoundedConfidenceAndUnknownStock() throws {
        let html = #"<meta property="og:type" content="product"><meta property="og:title" content="Boot"><meta property="og:url" content="https://new.example/p/1"><meta property="product:price:amount" content="10"><meta property="product:price:currency" content="EUR">"#
        let result = try #require(RetailStructuredDataExtractor().extract(page(html)).first)
        #expect(result.confidence == .boundedHTML)
        #expect(result.availability == .unknown)
    }

    @Test func microdataIsStructuredAndVisibleTextCannotOverrideStructuredPrice() throws {
        let html = #"""
        <div itemtype="https://schema.org/Product">
          Visible price: 1 UAH
          <meta itemprop="name" content="Boot">
          <meta itemprop="brand" content="Acme">
          <meta itemprop="sku" content="M-1">
          <meta itemprop="price" content="100">
          <meta itemprop="priceCurrency" content="UAH">
          <link itemprop="availability" href="https://schema.org/InStock">
          <link itemprop="url" href="https://unknown-shop.example/p/micro">
        </div>
        """#
        let result = try #require(RetailStructuredDataExtractor().extract(page(html)).first)
        #expect(result.price == Money(amount: 100, currency: "UAH"))
        #expect(result.confidence == .structuredMetadata)
        #expect(result.provenance == ["schema.org:microdata-or-rdfa"])
    }

    @Test func duplicateDiscoveryURLsCollapseToOneOffer() async throws {
        let url = URL(string: "https://unknown-shop.example/p/boot")!
        let provider = GenericRetailWebProvider(discovery: WebDiscoveryFake(urls: [url, url]),
            retriever: PageRetrieverFake(responses: [url: page(jsonLD())]))
        #expect(try await provider.search(request()).count == 1)
    }
}
