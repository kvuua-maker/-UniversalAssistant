# M6 Notification Observability Core

- Task ID: `M6-NOTIFICATION-OBSERVABILITY-CORE`
- Requirement IDs: 655, 683–684, 689, 699, 815.
- Capability: durable bounded redacted delivery events and selective APNs health state.
- Privacy: no device token, payload, authorization or provider response identifier is retained.
- Stop condition: backend and iOS regressions pass; checkpoint pushed.

## Verification

- Backend: PASS — 29 tests across 7 suites.
- iOS: PASS — 133 tests across 31 suites.
