# M6 Notification Policy Core — Requirement Scope Pack

- Task ID: `M6-NOTIFICATION-POLICY-CORE`
- Requirement IDs: 21–23, 38–49, 641–655, 695–700, 790–795, 815.
- Exact capability: enforce per-user/category preferences, meaningful-event deduplication, TTL, collapse replacement, thread identifiers and exact in-app tap routes before delivery.
- Selected path: backend-local E3 policy engine independent of APNs transport.
- Failure cases: global/category opt-out, duplicate event/version, stale notification, collapse mismatch, invalid or home-only routing.
- Privacy: policy keys contain opaque identifiers; no private notification body is retained or logged.
- Stop condition: focused backend and full iOS regressions pass; checkpoint committed and pushed.

## Verification

- Backend: PASS — 19 tests across 4 suites.
- iOS: PASS — 133 tests across 31 suites.
- Global/category opt-out, event/version dedupe, TTL, collapse replacement and exact app-route validation are covered.
