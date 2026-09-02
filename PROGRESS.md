# Progress

- Stage: M6 — Proactive Backend Notifications
- Completed: M0; M1 local implementation; M2 Apple local actions; M3 location/places/navigation/weather; M4 retail/fashion/grocery and Commerce Hub foundation; M5 services/rides/transport/tickets/hotels/travel/auth/degradation at local E3.
- Verified: Development build passes; iOS Swift Testing 133 tests across 31 suites passes; backend Swift Testing 19 tests across 4 suites passes.
- Blockers: live hotel/provider access remains capability-specific; no blocker for the provider-neutral hotel core.
- Mandatory addendum: Marketplace Commerce & Affiliate Hub accepted and persisted; implementation is routed into M4 without reopening M0/M1.
- Device tests: VOICE-001 and VOICE-002 queued; delivery build not issued yet.
- M5 completed blocks: bounded local-service request/fallback; truthful RideComparisonEngine; official ride-provider registry and credential-gated exact Uber route handoff; unified TransportEngine domain; ticket engine; hotel search core; travel-plan composition; local-first provider authentication boundary with scoped OAuth/Keychain semantics and exact official fallback.
- Canonical specs: full Master Spec v13.2 plus final Marketplace Commerce & Affiliate Hub addendum are persisted under `docs/` with verified hashes.
- M6 completed blocks: durable proactive job core; APNs device-token lifecycle; notification preference/dedupe/TTL/collapse/thread/exact-routing policy.
- Current: M6 APNs delivery core.
