# M4 Commerce Search Pipeline

- `CommerceSearchEngine` is actor-isolated and initializes only when a commerce request is made.
- Provider fan-out is capped, independent adapters run concurrently, and each provider has a bounded timeout and isolated failure.
- Identical concurrent requests share one in-flight task. Fresh results use a bounded TTL/LRU memory cache; expired entries trigger real provider work.
- Progressive search emits stable accumulated normalized results as providers finish and a distinct final update.
- `cancelAll()` cancels obsolete shared commerce work without coupling to non-commerce modules.
- Provider payload validation requires matching provider identity, nonnegative price, currency, exact HTTPS offer URL, relevant product identity and a fresh source timestamp. Stale and malformed offers are rejected.
- Total-cost calculation rejects unknown components and mixed currencies rather than silently omitting them.

Verification: Development simulator suite passed 70 tests in 18 suites on 2026-09-01, including in-flight deduplication, TTL expiry, provider cap, timeout/partial results, progressive completion, stale rejection and mixed-currency rejection.
