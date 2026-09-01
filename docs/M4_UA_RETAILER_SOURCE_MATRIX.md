# M4 Ukrainian Retailer and Supermarket Source Matrix

Last verified against official sources: 2026-09-01.

| Provider | Official evidence | Verified capabilities | Current status | Integration boundary |
|---|---|---|---|---|
| Сільпо | https://ai-factory.silpo.ua/docs/mcp | Official Streamable HTTP MCP at `https://mcp.silpo.ua/mcp`; OAuth 2.1 + PKCE; product batch/search/details, branch-specific catalogue/promotions, cart, delivery types/time slots and checkout links | `adapterReady` | All tools require guest OAuth. Product calls require current cart/branch context. Writes require action safety and provider readback. Tokens stay in backend/secure storage. |
| АТБ | https://www.atbmarket.com/ and https://www.atbmarket.com/delivery | Official consumer catalogue, regional delivery/pickup and exact consumer pages | `researched`, disabled | No public integration API, feed or affiliate interface verified. No scraping. Exact official-page fallback only when a verified URL is already available. |
| Фора | https://fora.ua/ | Official consumer catalogue, prices/promotions, address-dependent delivery and exact consumer pages | `researched`, disabled | No public integration API, feed or affiliate interface verified. No scraping. |
| Fozzy | https://fozzyshop.ua/ | Official consumer online supermarket and delivery pages | `researched`, disabled | No public integration API, feed or affiliate interface verified. No scraping. |

Registry policy: `researched` is evidence inventory, not executable integration. Only `adapterReady`, `implementedTested` or a deliberately scoped `fallback` may pass capability eligibility. Affiliate support is absent for all four records because no official affiliate evidence was verified.

Verification: Development build and simulator suite passed 91 tests in 22 suites on 2026-09-01. Live Сільпо OAuth/tool discovery and provider response mapping are the next implementation block.
