import Foundation

/// Read-only, zero-cost provider for packaged food. Open Prices observations
/// retain their observation date and are never promoted to live inventory.
struct OpenFoodFactsOpenPricesProvider: RetailProvider {
    let providerID = "open-food-facts-open-prices"
    private let session: URLSession
    private let userAgent = "UniversalAssistant/0.1 (+https://github.com/kvuua-maker/-UniversalAssistant)"

    init(session: URLSession = .shared) { self.session = session }

    func search(_ request: RetailSearchRequest) async throws -> [NormalizedOffer] {
        guard Self.isPackagedFood(request.identity.productType) || request.identity.gtin != nil else { return [] }
        let products = try await products(for: request)
        var output: [NormalizedOffer] = []
        for product in products.prefix(5) {
            guard let code = product.code, !code.isEmpty else { continue }
            let observations = (try? await prices(code: code)) ?? []
            for price in observations where price.location?.countryCode?.uppercased() == request.region.uppercased() {
                guard let observed = Self.dayFormatter.date(from: price.date), observed <= .now,
                      let purchaseURL = URL(string: "https://world.openfoodfacts.org/product/\(code)") else { continue }
                let candidate = ProductIdentity(
                    brand: product.brands?.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) },
                    model: product.productName, productType: request.identity.productType, sku: nil, gtin: code,
                    variant: .init(quantity: product.quantity, quantityUnit: product.quantityUnit)
                )
                let match = ProductIdentityResolver().match(query: request.identity, candidate: candidate)
                guard match.level != .unrelated else { continue }
                let sellerName = price.location?.brand ?? price.location?.name ?? "Open Prices observation"
                let proofURL = price.proof?.filePath.flatMap { URL(string: "https://prices.openfoodfacts.org/files/\($0)") }
                output.append(.init(
                    id: "openprices:\(price.id)", providerID: providerID, providerOfferID: String(price.id),
                    identity: candidate, identityMatch: match,
                    seller: .init(id: "openprices-location:\(price.locationID ?? 0)", name: sellerName),
                    availability: .unknown,
                    cost: .init(item: .init(amount: price.price, currency: price.currency),
                                shipping: .init(value: nil, knowledge: .unknown), tax: .init(value: nil, knowledge: .unknown),
                                duties: .init(value: nil, knowledge: .unknown), requiredOther: .init(value: nil, knowledge: .unknown)),
                    deliversToUkraine: nil, exactPurchaseURL: purchaseURL, sourceTimestamp: observed, fetchedAt: .now,
                    affiliateAttributionSupported: false, imageURL: product.imageURL.flatMap(URL.init(string:)),
                    productDescription: "Історичне спостереження ціни Open Prices; наявність не підтверджена.",
                    sourceConfidence: .structuredMetadata,
                    sourceProvenance: ["Open Food Facts", "Open Prices", proofURL?.absoluteString].compactMap { $0 }
                ))
            }
        }
        return output
    }

    private func products(for request: RetailSearchRequest) async throws -> [OFFProduct] {
        if let gtin = request.identity.gtin {
            let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(gtin).json?fields=code,product_name,brands,image_url,product_quantity,product_quantity_unit")!
            let payload: OFFProductResponse = try await get(url)
            return payload.status == 1 ? [payload.product].compactMap { $0 } : []
        }
        var components = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")!
        let query = [request.identity.brand, request.identity.model, request.identity.productType].compactMap { $0 }.joined(separator: " ")
        components.queryItems = [
            .init(name: "search_terms", value: query), .init(name: "search_simple", value: "1"),
            .init(name: "action", value: "process"), .init(name: "json", value: "1"), .init(name: "page_size", value: "5"),
            .init(name: "fields", value: "code,product_name,brands,image_url,product_quantity,product_quantity_unit")
        ]
        let payload: OFFSearchResponse = try await get(components.url!)
        return payload.products
    }

    private func prices(code: String) async throws -> [OpenPrice] {
        var components = URLComponents(string: "https://prices.openfoodfacts.org/api/v1/prices")!
        components.queryItems = [.init(name: "product_code", value: code), .init(name: "page_size", value: "20")]
        let payload: OpenPricesResponse = try await get(components.url!)
        return payload.items
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url, timeoutInterval: 6)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count <= 2_000_000 else { throw RetailProviderError.unavailable }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func isPackagedFood(_ text: String) -> Bool {
        let value = text.lowercased()
        return ["grocery", "groceries", "food", "продукт", "їжа", "напій", "бакалія"].contains(where: value.contains)
    }

    private static let dayFormatter: DateFormatter = {
        let value = DateFormatter(); value.locale = Locale(identifier: "en_US_POSIX"); value.timeZone = TimeZone(secondsFromGMT: 0); value.dateFormat = "yyyy-MM-dd"; return value
    }()
}

private struct OFFProductResponse: Decodable { let status: Int; let product: OFFProduct? }
private struct OFFSearchResponse: Decodable { let products: [OFFProduct] }
private struct OFFProduct: Decodable {
    let code: String?; let productName: String?; let brands: String?; let imageURL: String?
    let quantity: Decimal?; let quantityUnit: String?
    enum CodingKeys: String, CodingKey { case code, productName = "product_name", brands, imageURL = "image_url", quantity = "product_quantity", quantityUnit = "product_quantity_unit" }
}
private struct OpenPricesResponse: Decodable { let items: [OpenPrice] }
private struct OpenPrice: Decodable {
    let id: Int; let price: Decimal; let currency: String; let date: String
    let locationID: Int?; let location: Location?; let proof: Proof?
    struct Location: Decodable {
        let name: String?; let brand: String?; let countryCode: String?
        enum CodingKeys: String, CodingKey { case name = "osm_name", brand = "osm_brand", countryCode = "osm_address_country_code" }
    }
    struct Proof: Decodable { let filePath: String?; enum CodingKeys: String, CodingKey { case filePath = "file_path" } }
    enum CodingKeys: String, CodingKey { case id, price, currency, date, locationID = "location_id", location, proof }
}
