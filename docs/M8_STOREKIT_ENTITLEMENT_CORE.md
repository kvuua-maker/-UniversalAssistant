# M8 StoreKit 2 Entitlement Core

- Requirements: 727–736, 817, 1606–1614.
- Premium unlocks only from verified subscription evidence. Unverified client data never becomes entitlement authority.
- Active and valid grace-period subscriptions enable Premium; billing retry, expiration and revocation downgrade gracefully.
- Downgrade disables gated capabilities but always preserves read/export access to owned data and never corrupts or deletes it.
- Restore uses `AppStore.sync()` through a bounded protocol. Storefront product display/purchase must use StoreKit product metadata; no price is hard-coded in business logic.
- External gate: real products, localized price/terms, purchase, renewal, refund, grace/billing and server notification verification require App Store Connect configuration and StoreKit sandbox/device evidence.
- Local verification: 180 iOS tests across 45 suites and 29 backend tests across 7 suites passed on 2026-09-02.
- Exit state: `SUCCESS` for the bounded local E3 entitlement contract.
