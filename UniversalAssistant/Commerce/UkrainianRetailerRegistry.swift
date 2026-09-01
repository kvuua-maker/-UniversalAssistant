import Foundation

enum UkrainianRetailerRegistry {
    static let lastVerified = Date(timeIntervalSince1970: 1_788_220_800) // 2026-09-01 UTC

    static let records: [ProviderCapabilityRecord] = [
        .init(
            id: "ua.silpo.mcp", displayName: "Сільпо", regions: ["UA"],
            capabilities: [.search, .catalog, .exactProduct, .price, .availability, .shipping, .cart, .checkoutHandoff],
            requiresCredentials: true, requiresOwnerRegistration: false, requiresApproval: false,
            rateLimitSummary: "HTTP 429; per-user bounded backoff required",
            restrictions: [
                "Official Streamable HTTP MCP only: https://mcp.silpo.ua/mcp",
                "OAuth 2.1 Authorization Code + PKCE; all tools require guest authorization",
                "Branch/cart context required for product availability and promotions",
                "Cart mutations require explicit write-action safety; checkout remains Сільпо"
            ],
            status: .adapterReady, fallback: "Exact official silpo.ua product/checkout link when returned by provider",
            lastOfficialVerification: lastVerified, enabled: true,
            officialDocumentationURL: URL(string: "https://ai-factory.silpo.ua/docs/mcp")
        ),
        researchedConsumerCatalog(
            id: "ua.atb.web", name: "АТБ", url: "https://www.atbmarket.com/",
            restrictions: ["Official consumer catalogue and delivery confirmed", "No public integration API or affiliate interface verified"]
        ),
        researchedConsumerCatalog(
            id: "ua.fora.web", name: "Фора", url: "https://fora.ua/",
            restrictions: ["Official consumer catalogue, prices, promotions and delivery confirmed", "No public integration API or affiliate interface verified"]
        ),
        researchedConsumerCatalog(
            id: "ua.fozzy.web", name: "Fozzy", url: "https://fozzyshop.ua/",
            restrictions: ["Official consumer online supermarket confirmed", "No public integration API or affiliate interface verified"]
        )
    ]

    private static func researchedConsumerCatalog(
        id: String, name: String, url: String, restrictions: [String]
    ) -> ProviderCapabilityRecord {
        .init(
            id: id, displayName: name, regions: ["UA"], capabilities: [.catalog, .price, .exactDeepLink],
            requiresCredentials: false, requiresOwnerRegistration: false, requiresApproval: false,
            restrictions: restrictions, status: .researched,
            fallback: "Open an exact official consumer page only when a verified URL is already available",
            lastOfficialVerification: lastVerified, enabled: false,
            officialDocumentationURL: URL(string: url)
        )
    }
}
