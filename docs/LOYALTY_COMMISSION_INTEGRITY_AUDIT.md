# Loyalty / Discount / Attribution / Commission Integrity — evidence audit

One-time evidence-backed audit completed 2026-09-03. Existing Loyalty/Personal Price/Attribution Core was preserved and extended in place.

| Capability | Before | Evidence | Gap disposition |
|---|---|---|---|
| Loyalty card/account/personal price | ALREADY_IMPLEMENTED | LoyaltyPersonalPriceCore.swift; 10 original behavioral tests | preserved |
| Versioned attribution strategy | ALREADY_IMPLEMENTED | AttributionStrategyRegistry/Evaluator | preserved |
| Typed economic separation and stacking | PARTIAL | existing benefit kinds lacked funding/stacking matrix | extended in same Core |
| Checkout attribution integrity | PARTIAL | eligibility existed; checkout path state absent | extended in same Core |
| Commission basis/lifecycle/refunds | PARTIAL | backend exact ledger existed; client quote economics absent | extended without replacing ledger |
| Account-scope cache invalidation | PARTIAL | card persistence existed | scoped cache and disconnect invalidation added |
| Partner-specific real stacking/checkout | LIVE_VERIFICATION_REQUIRED | no owner/provider contracts or accounts available | exact queue item; UNKNOWN locally |

Locally available PARTIAL/MISSING gaps: 0 after implementation. No partner rule is inferred from generic affiliate knowledge.
