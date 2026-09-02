# M9 Remote Config, Feature Flags and Cost/Quota Core

The backend accepts only validated, monotonically versioned runtime policy snapshots with effective/expiry bounds and a source reference. Feature decisions are typed and scoped by country/category; missing, future, expired, disabled or out-of-scope policy fails closed. No business activation or price is hardcoded.

Cost/quota reservations use an actor for atomic accounting, `Decimal` for provider-reported cost, explicit currency matching, bounded calls/cost and operation-ID idempotency. Denials are typed and audited. Policy values are injected configuration and may change without rewriting core logic; secrets and user content are not part of either contract.
