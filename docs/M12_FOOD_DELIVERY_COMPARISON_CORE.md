# M12 Food Delivery Comparison Core

Requirements MS-1043–1049. Status: VERIFIED_LOCAL; provider-authorized consumer data/live ordering verification is READY_FOR_LIVE_VERIFICATION.

`FoodDeliveryComparisonEngine` fans out across at most six modular `FoodDeliveryProvider` adapters concurrently with a bounded timeout and cancellation. Only fresh, provider-attributed, availability-verified HTTPS offers enter results. A hard maximum-delivery constraint rejects late or unverified ETA. Comparable offers require verified item price, every required fee, common currency and verified ETA; incomplete offers remain explicitly separated. Ranking uses exact `Decimal` delivered total and ETA, not menu price alone. Provider failure produces truthful coverage metadata and cannot suppress a verified alternative.

Ordering remains a confirmed exact-provider handoff. Without confirmation the engine returns `confirmationRequired`; it never reports that an order was placed. Additional regional providers implement the same normalized protocol.

Current official audit found Glovo Partner APIs for partner-side catalog, price/availability, outlet and order operations, with credentials from an account manager and sandbox/E2E coordination. It did not establish unrestricted consumer comparison/order access. Bolt publishes an official Food developer portal and merchant onboarding, but live capability remains partner authorized. Sources: `https://qcommerce.developer.glovoapp.com/en/documentation/api-partner-api-overview`, `https://qcommerce.developer.glovoapp.com/en/documentation/catalog-api-use-cases`, `https://developer.bolt.eu/food/main/`, `https://bolt.eu/food/merchant/`.

Behavioral evidence in `FoodDeliveryComparisonEngineTests` covers full delivered-price ranking, hard ETA, incomplete facts, partial provider failure, bounded timeout/cancellation and no-fake-order confirmation. Full regression on 2026-09-02 passed 300 iOS tests across 75 suites and 79 backend tests across 22 suites. Commit evidence is the atomic commit containing this document and referenced implementation/tests.
