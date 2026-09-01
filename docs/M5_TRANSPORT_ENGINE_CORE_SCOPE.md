# M5 Unified Transport Engine Core

- `TransportEngine` normalizes ride, public-transit, walking and driving options without coupling the domain to a network provider.
- Evidence explicitly distinguishes estimates, schedules and real-time observations. Scheduled data cannot prove live availability, even when a provider labels the scheduled service available.
- Evidence must be fresh and source-attributed. Stale, future-skewed or source-less ride evidence cannot enter strict live comparison.
- Departure, arrival, duration, price and transfer limits are hard constraints: a missing field does not satisfy a requested limit.
- Unavailable options are excluded. A request for verified availability accepts only fresh real-time evidence explicitly marked available.
- Ranking prefers earlier known arrival, then shorter known duration, then lower known price, preserving stable input order for ties.
- Existing `RideOffer` values can enter the unified domain only with their original timestamp, provider identity, explicit fields and exact handoff URL intact.
- The engine performs no network work, initializes no provider at startup, and makes no claim of live public-transport access.

Verification is recorded in repository state after the Development simulator build and complete iOS/backend test runs pass.
