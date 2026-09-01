# M5 Truthful Ride Comparison Core

- `ComparableServiceOffer` establishes the shared evidence surface for ride, courier, tow, ticket, hotel and future service comparison without coupling the core to provider SDKs.
- `RideOffer` keeps price, pickup wait, estimated arrival, availability, class, capabilities and provider evidence timestamp separate; absent values remain absent.
- `RideComparisonEngine` accepts only fresh, explicitly available offers and applies budget, maximum wait and required capabilities as hard filters.
- Modes cover cheapest, fastest, optimal, comfort, large vehicle, child seat, pet friendly and luggage. Specialized modes require an explicitly reported capability and never infer one from provider or class.
- Cheapest comparison rejects mixed currencies until a verified FX normalization path is supplied. Stable input order resolves equal comparisons.
- The engine performs no network work and initializes no provider at app startup.

Verification: Development simulator build and all 100 iOS tests in 24 suites passed on 2026-09-01. This checkpoint is a comparison domain, not a claim of live Uklon, Bolt or Uber price/ETA access.
