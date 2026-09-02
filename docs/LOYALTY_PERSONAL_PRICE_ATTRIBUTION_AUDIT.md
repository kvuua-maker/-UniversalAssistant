# Loyalty / Personal Price / Attribution Preservation — Targeted Audit

Date: 2026-09-02.

## Initial evidence matrix

| Capability | Status | Existing production/test evidence | Gap |
| --- | --- | --- | --- |
| Connected store account OAuth | ALREADY_IMPLEMENTED | ProviderAuthenticationBoundary, ConnectedAccountsHub; exact-scope/expiry/revoke/restart tests | Merchant-specific loyalty scopes/client remain live-contract specific |
| Loyalty card fallback | MISSING | No normalized card persistence | Required minimal merchant/card identity |
| Personal price | MISSING | NormalizedOffer had one public price only | Separate verified effective price/benefits/delivery evidence |
| Attribution preservation | PARTIAL | AffiliatePurchaseRouter preserves exact URL parameters; ConversionLedger handles refund adjustments | No merchant-program eligibility/loyalty/coupon/competing-attribution rules |
| Strategy registry | MISSING | Commercial agreements are versioned server-side | No typed persisted tracking/eligibility/priority policy |
| Ranking | PARTIAL | OfferRanker excludes commission | Did not use verified user-specific price |

## Final evidence matrix

| Capability | Status | Production evidence | Behavioral evidence |
| --- | --- | --- | --- |
| Connected store account | ALREADY_IMPLEMENTED | Existing OAuth/Keychain/ConnectedAccountsHub is reused; MerchantLoyaltyProvider adds only the permitted-benefits boundary | ConnectedAccountsHubTests; existingCustomerLoginAndLoyaltyDoNotEraseAttribution |
| Loyalty card fallback | VERIFIED_LOCAL | LoyaltyIdentity, LoyaltyCard, LocalLoyaltyPersistence and deterministic merchant/card dedup | loyaltyCardDeduplicatesAndPersistsAcrossRestart |
| Personal price | VERIFIED_LOCAL | VerifiedPersonalPrice keeps public/effective price separately; only verified current personal-price/coupon/reward values and compatible delivery currency apply | verifiedBenefitsProduceSeparatePublicAndEffectivePrice; unknownDiscountNeverChangesEffectivePrice |
| Identity separation | VERIFIED_LOCAL | LoyaltyIdentity has no customer or referral field; AttributionContext has no card/account secret and evaluates a separately supplied referral timestamp | existingCustomerLoginAndLoyaltyDoNotEraseAttribution |
| Strategy registry | VERIFIED_LOCAL | versioned AttributionStrategy and durable AttributionStrategyRegistry capture methods/window/customer/loyalty/coupon/voucher/priority/exclusions/refund reversal/evidence/effective period | versionedAttributionStrategyPersistsAcrossRestart |
| Attribution truth | VERIFIED_LOCAL | evaluator emits ELIGIBLE, NOT_ELIGIBLE or UNKNOWN; preserves competing attribution and never forces a click | coupon/returning/expiry/competing/missing-contract/refund tests |
| Exclusive voucher/handoff compatibility | VERIFIED_LOCAL | exclusiveVoucher is an explicit official tracking method; existing AffiliatePurchaseRouter remains the only allowlisted exact destination mutator | exclusiveVoucherIsAnExplicitTrackingMethod; AffiliatePurchaseRouterTests |
| Ranking | VERIFIED_LOCAL | OfferRanker uses verified effective price when present and remains independent of affiliate/commission values | NormalizedOfferTests plus personal-price tests |

No merchant password is accepted or stored. A loyalty card does not assert a discount. Existing customer/login/card/coupon never deletes referral state, but also never guarantees commission. Refund/cancellation policy is an explicit reversal contract and the existing append-only ConversionLedger remains authoritative for actual financial adjustments.
