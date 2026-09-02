# M6 Local Acceptance — Proactive Backend Notifications

M6 requirement 815 is accepted at local evidence level E3.

## Accepted scope

- Durable scheduler/queue with restart persistence, deduplication, bounded retry, expiration, linking/cancellation and dead-letter handling.
- APNs token lifecycle, notification preferences, meaningful deduplication, TTL, collapse/thread identifiers and exact tap routing.
- Credential-gated APNs delivery contracts with explicit outcomes and invalid-token handling.
- Traffic/weather/business/product/ticket watches using fresh evidence and meaningful-change thresholds.
- Bounded privacy-safe delivery observability and selective dependency health.

## Verification evidence

- Backend: 29 tests across 7 suites passed on 2026-09-02.
- iOS: 133 tests across 31 suites passed.
- M6 commits `dcedbeb`, `02866ec`, `7c47df7`, `f3553f6`, `cfe78c0`, and `85aea55` are on `origin/main`.

No live APNs/provider polling is claimed. Apple credentials, deployed HTTP/2 transport, production storage and provider access remain E4/deployment gates. M6 is frozen complete; M7 begins with `AppCapabilityRegistry`.
