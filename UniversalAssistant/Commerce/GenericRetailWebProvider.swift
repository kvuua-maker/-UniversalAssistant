import Foundation

protocol RetailWebDiscovery: Sendable {
    func productPageURLs(for request: RetailSearchRequest) async throws -> [URL]
}

protocol RetailDiscoveryTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionRetailDiscoveryTransport: RetailDiscoveryTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw RetailPageFailure.unavailable }
        return (data, response)
    }
}

struct ConfiguredRetailWebDiscovery: RetailWebDiscovery {
    let endpoint: URL
    let bearerToken: String
    let transport: any RetailDiscoveryTransport
    var maximumResults = 12

    init(endpoint: URL, bearerToken: String, transport: any RetailDiscoveryTransport = URLSessionRetailDiscoveryTransport()) {
        self.endpoint = endpoint; self.bearerToken = bearerToken; self.transport = transport
    }

    func productPageURLs(for request: RetailSearchRequest) async throws -> [URL] {
        guard endpoint.scheme == "https", endpoint.host != nil, !bearerToken.isEmpty,
              (1...50).contains(maximumResults) else { throw RetailPageFailure.invalidURL }
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        let identity = request.identity
        let query = [identity.brand, identity.model, identity.productType,
                     identity.variant.size, identity.variant.color].compactMap { $0 }.joined(separator: " ")
        components?.queryItems = [.init(name: "q", value: query),
                                  .init(name: "type", value: "product"),
                                  .init(name: "limit", value: String(maximumResults))]
        guard let url = components?.url else { throw RetailPageFailure.invalidURL }
        var webRequest = URLRequest(url: url)
        webRequest.timeoutInterval = 8
        webRequest.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport.data(for: webRequest)
        guard (200...299).contains(response.statusCode),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]] else { throw RetailPageFailure.unavailable }
        var seen: Set<String> = []
        return results.compactMap { $0["url"] as? String }.compactMap(URL.init(string:))
            .filter(URLSessionRetailPageRetriever.allowed)
            .filter { seen.insert($0.absoluteString).inserted }
            .prefix(maximumResults).map { $0 }
    }
}

protocol RetailPageRetrieving: Sendable {
    func retrieve(_ url: URL) async throws -> RetailPageResponse
}

struct RetailPageResponse: Equatable, Sendable {
    let finalURL: URL
    let html: String
    let fetchedAt: Date
    let sourceTimestamp: Date?
}

enum RetailPageFailure: String, Error, Equatable, Sendable {
    case invalidURL, blocked, loginRequired, captcha, dynamicPage, unavailable, oversized, malformed
}

enum RetailExtractionConfidence: Int, Comparable, Sendable {
    case boundedHTML = 1, structuredMetadata = 2, verifiedPartner = 3
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct ExtractedRetailProduct: Equatable, Sendable {
    let name: String
    var brand: String?
    var description: String?
    var sku: String?
    var gtin: String?
    var model: String?
    var imageURL: URL?
    var size: String?
    var color: String?
    var price: Money?
    var originalPrice: Money?
    var availability: OfferAvailability = .unknown
    var seller: String?
    var deliveryInformation: String?
    let canonicalURL: URL
    let sourceTimestamp: Date
    let confidence: RetailExtractionConfidence
    let provenance: [String]
}

struct GenericRetailSearchResult: Sendable {
    let offers: [NormalizedOffer]
    let failures: [URL: RetailPageFailure]
}

struct URLSessionRetailPageRetriever: RetailPageRetrieving {
    var maximumBytes = 2_000_000

    func retrieve(_ url: URL) async throws -> RetailPageResponse {
        guard Self.allowed(url) else { throw RetailPageFailure.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw RetailPageFailure.unavailable
        }
        guard data.count <= maximumBytes else { throw RetailPageFailure.oversized }
        let mime = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        guard mime.contains("html"), let html = String(data: data, encoding: .utf8) else {
            throw RetailPageFailure.malformed
        }
        return .init(finalURL: http.url ?? url, html: html, fetchedAt: .now,
                     sourceTimestamp: Self.httpDate(http.value(forHTTPHeaderField: "Last-Modified")))
    }

    static func allowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
              !host.isEmpty, !url.path.isEmpty, url.path != "/" else { return false }
        if host == "localhost" || host.hasSuffix(".local") { return false }
        let parts = host.split(separator: ".")
        if parts.count == 4, parts.allSatisfy({ Int($0).map { (0...255).contains($0) } ?? false }) { return false }
        return true
    }

    private static func httpDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: value)
    }
}

struct RetailStructuredDataExtractor: Sendable {
    func extract(_ response: RetailPageResponse) throws -> [ExtractedRetailProduct] {
        let lower = response.html.lowercased()
        if lower.contains("captcha") || lower.contains("verify you are human") { throw RetailPageFailure.captcha }
        if lower.contains("login required") || lower.contains("sign in to continue") { throw RetailPageFailure.loginRequired }
        if lower.contains("access denied") || lower.contains("request blocked") { throw RetailPageFailure.blocked }

        var products = jsonLD(in: response)
        if products.isEmpty, let product = microdata(in: response) { products = [product] }
        if products.isEmpty, let product = openGraph(in: response) { products = [product] }
        if products.isEmpty {
            if lower.contains("application/ld+json") { throw RetailPageFailure.malformed }
            if lower.contains("<script") { throw RetailPageFailure.dynamicPage }
            throw RetailPageFailure.malformed
        }
        return products
    }

    private func jsonLD(in response: RetailPageResponse) -> [ExtractedRetailProduct] {
        let pattern = #"<script[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>([\s\S]*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let source = response.html as NSString
        return regex.matches(in: response.html, range: NSRange(location: 0, length: source.length)).flatMap { match -> [ExtractedRetailProduct] in
            guard match.numberOfRanges > 1,
                  let data = source.substring(with: match.range(at: 1)).data(using: .utf8),
                  let value = try? JSONSerialization.jsonObject(with: data) else { return [] }
            return productObjects(value).compactMap { product($0, response: response) }
        }
    }

    private func productObjects(_ value: Any) -> [[String: Any]] {
        if let array = value as? [Any] { return array.flatMap(productObjects) }
        guard let object = value as? [String: Any] else { return [] }
        if let graph = object["@graph"] { return productObjects(graph) }
        var types = (object["@type"] as? [Any])?.compactMap { $0 as? String } ?? []
        if let type = object["@type"] as? String { types.append(type) }
        return types.contains(where: { $0.caseInsensitiveCompare("Product") == .orderedSame }) ? [object] : []
    }

    private func product(_ object: [String: Any], response: RetailPageResponse) -> ExtractedRetailProduct? {
        guard let name = text(object["name"]), !name.isEmpty else { return nil }
        let offers = (object["offers"] as? [String: Any]) ?? (object["offers"] as? [[String: Any]])?.first
        let canonical = URL(string: text(object["url"]) ?? "", relativeTo: response.finalURL)?.absoluteURL ?? response.finalURL
        guard URLSessionRetailPageRetriever.allowed(canonical) else { return nil }
        let currency = text(offers?["priceCurrency"])?.uppercased()
        let price = decimal(offers?["price"]).flatMap { amount in currency.map { Money(amount: amount, currency: $0) } }
        let original = decimal(offers?["highPrice"]).flatMap { amount in currency.map { Money(amount: amount, currency: $0) } }
        let image = text(object["image"]) ?? (object["image"] as? [String])?.first
        let availability = availability(text(offers?["availability"]))
        let sellerObject = offers?["seller"] as? [String: Any]
        let timestamp = isoDate(text(object["dateModified"])) ?? response.sourceTimestamp ?? response.fetchedAt
        let gtin = text(object["gtin13"]) ?? text(object["gtin12"]) ?? text(object["gtin14"]) ?? text(object["gtin"])
        return .init(name: name, brand: text((object["brand"] as? [String: Any])?["name"]) ?? text(object["brand"]),
                     description: text(object["description"]), sku: text(object["sku"]), gtin: gtin,
                     model: text(object["model"]), imageURL: image.flatMap { URL(string: $0, relativeTo: response.finalURL)?.absoluteURL },
                     size: text(object["size"]), color: text(object["color"]), price: price, originalPrice: original,
                     availability: availability, seller: text(sellerObject?["name"]), deliveryInformation: text(offers?["shippingDetails"]),
                     canonicalURL: canonical, sourceTimestamp: timestamp, confidence: .structuredMetadata,
                     provenance: ["json-ld:Product", "schema.org:Offer"])
    }

    private func openGraph(in response: RetailPageResponse) -> ExtractedRetailProduct? {
        func meta(_ property: String) -> String? {
            let escaped = NSRegularExpression.escapedPattern(for: property)
            let pattern = #"<meta[^>]+(?:property|name)=["']"# + escaped + #"["'][^>]+content=["']([^"']+)["'][^>]*>"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: response.html, range: NSRange(response.html.startIndex..., in: response.html)),
                  let range = Range(match.range(at: 1), in: response.html) else { return nil }
            return String(response.html[range])
        }
        guard meta("og:type")?.lowercased().contains("product") == true, let name = meta("og:title") else { return nil }
        let canonical = meta("og:url").flatMap { URL(string: $0, relativeTo: response.finalURL)?.absoluteURL } ?? response.finalURL
        guard URLSessionRetailPageRetriever.allowed(canonical) else { return nil }
        let currency = meta("product:price:currency")?.uppercased()
        let price = decimal(meta("product:price:amount")).flatMap { amount in currency.map { Money(amount: amount, currency: $0) } }
        return .init(name: name, description: meta("og:description"), imageURL: meta("og:image").flatMap(URL.init(string:)),
                     price: price, canonicalURL: canonical, sourceTimestamp: response.sourceTimestamp ?? response.fetchedAt,
                     confidence: .boundedHTML, provenance: ["opengraph"])
    }

    private func microdata(in response: RetailPageResponse) -> ExtractedRetailProduct? {
        func value(_ key: String) -> String? {
            let escaped = NSRegularExpression.escapedPattern(for: key)
            let pattern = #"<(?:meta|link)[^>]+(?:itemprop|property)=["']"# + escaped + #"["'][^>]+(?:content|href)=["']([^"']+)["'][^>]*>"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: response.html, range: NSRange(response.html.startIndex..., in: response.html)),
                  let range = Range(match.range(at: 1), in: response.html) else { return nil }
            return String(response.html[range])
        }
        guard response.html.range(of: #"itemtype=["']https?://schema.org/Product["']"#,
                                  options: [.regularExpression, .caseInsensitive]) != nil,
              let name = value("name") else { return nil }
        let canonical = value("url").flatMap { URL(string: $0, relativeTo: response.finalURL)?.absoluteURL } ?? response.finalURL
        guard URLSessionRetailPageRetriever.allowed(canonical) else { return nil }
        let currency = value("priceCurrency")?.uppercased()
        let price = decimal(value("price")).flatMap { amount in currency.map { Money(amount: amount, currency: $0) } }
        return .init(name: name, brand: value("brand"), description: value("description"),
                     sku: value("sku"), gtin: value("gtin13") ?? value("gtin"),
                     model: value("model"), imageURL: value("image").flatMap(URL.init(string:)),
                     size: value("size"), color: value("color"), price: price,
                     availability: availability(value("availability")), seller: value("seller"),
                     deliveryInformation: value("shippingDetails"), canonicalURL: canonical,
                     sourceTimestamp: response.sourceTimestamp ?? response.fetchedAt,
                     confidence: .structuredMetadata, provenance: ["schema.org:microdata-or-rdfa"])
    }

    private func text(_ value: Any?) -> String? {
        if let value = value as? String { return value.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }
    private func decimal(_ value: Any?) -> Decimal? { text(value).flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) } }
    private func isoDate(_ value: String?) -> Date? { value.flatMap { ISO8601DateFormatter().date(from: $0) } }
    private func availability(_ value: String?) -> OfferAvailability {
        let value = value?.lowercased() ?? ""
        if value.contains("instock") { return .inStock }
        if value.contains("outofstock") || value.contains("soldout") { return .outOfStock }
        if value.contains("preorder") { return .preorder }
        return .unknown
    }
}

struct GenericRetailWebProvider: RetailProvider {
    let providerID = "generic-retail-web"
    let discovery: any RetailWebDiscovery
    let retriever: any RetailPageRetrieving
    var maximumPages = 8
    var maximumAge: TimeInterval = 24 * 60 * 60

    func search(_ request: RetailSearchRequest) async throws -> [NormalizedOffer] {
        let urls = try await discovery.productPageURLs(for: request)
        let pages = Array(urls.filter(URLSessionRetailPageRetriever.allowed).prefix(maximumPages))
        guard !pages.isEmpty else { return [] }
        let result = await withTaskGroup(of: [NormalizedOffer]?.self) { group in
            for url in pages {
                group.addTask {
                    guard let response = try? await retriever.retrieve(url),
                          let products = try? RetailStructuredDataExtractor().extract(response) else { return nil }
                    return products.compactMap { normalize($0, request: request, fetchedAt: response.fetchedAt) }
                }
            }
            var offers: [NormalizedOffer] = [], retrieved = false
            for await batch in group {
                guard let batch else { continue }
                retrieved = true; offers += batch
            }
            return (offers, retrieved)
        }
        guard result.1 else { throw RetailPageFailure.unavailable }
        return OfferRanker().rank(OfferDeduplicator().deduplicate(result.0))
    }

    private func normalize(_ product: ExtractedRetailProduct, request: RetailSearchRequest, fetchedAt: Date) -> NormalizedOffer? {
        guard let price = product.price, fetchedAt.timeIntervalSince(product.sourceTimestamp) <= maximumAge,
              fetchedAt.timeIntervalSince(product.sourceTimestamp) >= -60 else { return nil }
        let gtin = product.gtin.flatMap { GTINValidator().isValid($0) ? $0 : nil }
        let identity = ProductIdentity(brand: product.brand, model: product.model, productType: product.name,
            sku: product.sku, gtin: gtin,
            variant: .init(size: product.size, color: product.color))
        guard let validated = try? identity.validated(), let host = product.canonicalURL.host?.lowercased() else { return nil }
        let match = ProductIdentityResolver().match(query: request.identity, candidate: validated)
        let unknown = CostComponent(value: nil, knowledge: .unknown)
        return .init(id: "web:\(host):\(product.sku ?? product.canonicalURL.absoluteString)",
                     providerID: providerID, providerOfferID: product.canonicalURL.absoluteString,
                     identity: validated, identityMatch: match,
                     seller: .init(id: host, name: product.seller ?? host),
                     availability: product.availability,
                     cost: .init(item: price, shipping: unknown, tax: unknown, duties: unknown, requiredOther: unknown),
                     exactPurchaseURL: product.canonicalURL, sourceTimestamp: product.sourceTimestamp,
                     fetchedAt: fetchedAt, affiliateAttributionSupported: false,
                     imageURL: product.imageURL, originalItemPrice: product.originalPrice,
                     productDescription: product.description, deliveryInformation: product.deliveryInformation,
                     sourceConfidence: product.confidence, sourceProvenance: product.provenance)
    }
}
