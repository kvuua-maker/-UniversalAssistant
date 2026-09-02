# Generic Retail Web Discovery & Extraction — Targeted Audit

Date: 2026-09-02. Policy: generic extraction is a bounded fallback behind official API/partner/feed providers, never a bypass of access restrictions and never evidence of affiliate eligibility.

## Pre-implementation evidence matrix

| Capability | Status | Existing implementation | Test evidence | Commit evidence | Gap |
| --- | --- | --- | --- | --- | --- |
| Generic discovery of unknown retailer | MISSING | ControlledWebSearchHandoff created a browser search URL only | ControlledWebSearchHandoffTests | 27ad853 | No product URL discovery or retrieval |
| Product page retrieval and validation | MISSING | Exact known offer URL validation only | AffiliatePurchaseRouterTests | 0d2020e | No bounded HTML retrieval |
| Structured extraction/normalization | MISSING | Provider-supplied NormalizedOffer only | NormalizedOfferTests | d3fd2a2 | No JSON-LD/microdata/RDFa/OpenGraph extraction |
| Truth/failure semantics | PARTIAL | Stale provider offers rejected | CommerceSearchEngineTests | 6268ef9 | CAPTCHA/login/dynamic/malformed page not distinguished from no product |
| Native card and truthful handoff | PARTIAL | Native card and exact handoff existed for provider offers | CommercePresentationTests, AffiliatePurchaseRouterTests | d55890f | No unknown-retailer normalized input |

## Post-implementation evidence matrix

| Capability | Status | Production evidence | Behavioral evidence |
| --- | --- | --- | --- |
| Generic discovery | VERIFIED_LOCAL | ConfiguredRetailWebDiscovery forms a typed product-only query against an owner-configured HTTPS search service, accepts previously unknown domains, deduplicates URLs and rejects unsafe/homepage URLs | configuredDiscoveryFindsUnknownDomainsWithoutHardcodedRetailers |
| Retrieval/domain validation | VERIFIED_LOCAL | URLSessionRetailPageRetriever enforces HTTPS/exact path, blocks local/IP destinations, bounds timeout/bytes/content type and propagates page failure | unsafeOrHomepageDiscoveryDestinationsAreRejectedBeforeRetrieval; unavailableSearchResultPageProducesNoFabricatedOffer |
| Structured extraction | VERIFIED_LOCAL | RetailStructuredDataExtractor prefers schema.org JSON-LD, supports graph/multiple variants, microdata/RDFa-style metadata and bounded OpenGraph fallback | unknownRetailerJSONLDReachesNormalizedNativeCardAndTruthfulHandoff; variantsStaySeparateAndUnknownStockStaysUnknown; microdataIsStructuredAndVisibleTextCannotOverrideStructuredPrice; openGraphFallbackHasLowerBoundedConfidenceAndUnknownStock |
| Truth/freshness/confidence | VERIFIED_LOCAL | price, original price, availability, description, image, identity/variant, seller, delivery, timestamp, provenance and confidence normalize without inferred stock; stale evidence is dropped and inaccessible pages become provider failure | price/out-of-stock, unknown variant stock, stale, CAPTCHA/login/blocked/dynamic/malformed tests |
| Dedup/ranking/provider preference | VERIFIED_LOCAL | OfferDeduplicator collapses exact URL duplicates and strong same-seller identity while preserving variants and preferring API/partner evidence over generic-web duplicate; OfferRanker remains commission-independent | duplicateDiscoveryURLsCollapseToOneOffer; partnerResultReplacesGenericDuplicateButDistinctVariantRemains; dedupDoesNotMergeDifferentSellers |
| Native result/action/affiliate truth | VERIFIED_LOCAL | GenericRetailWebProvider conforms to existing RetailProvider, feeds NormalizedOffer/CommerceOfferPresentation and AffiliatePurchaseRouter; generic offers always carry no affiliate attribution and exact product-page handoff | unknownRetailerJSONLDReachesNormalizedNativeCardAndTruthfulHandoff; CommercePresentationTests; AffiliatePurchaseRouterTests |

Search snippets are discovery hints only: no snippet field enters NormalizedOffer. A page must be retrieved and supply supported metadata. A blocked, unavailable, dynamic-only or malformed page raises provider failure and is never translated to out-of-stock. Unknown variant stock remains UNKNOWN. Live verification requires an owner-selected lawful search service and controlled public product pages; it is queued separately.
