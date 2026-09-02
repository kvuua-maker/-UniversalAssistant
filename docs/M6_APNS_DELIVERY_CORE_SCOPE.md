# M6 APNs Delivery Core — Requirement Scope Pack

- Task ID: `M6-APNS-DELIVERY-CORE`
- Requirement IDs: 21–23, 38–49, 385–387, 641–655, 688–699, 755–761, 790–795, 815.
- Exact capability: build bounded APNs HTTP/2 request contracts with environment endpoint, topic, authorization, TTL, collapse ID, thread and exact route; classify provider responses for success, invalid token, retry and terminal rejection.
- Selected path: transport-injected backend E3 core; no live APNs claim without Apple signing credentials.
- Security/privacy: authorization is injected, never persisted/logged; payload is limited to 4096 bytes and exact app routes.
- Stop condition: backend contract tests and iOS regressions pass; live credential remains a documented E4 gate.

## Verification

- Backend: PASS — 23 tests across 5 suites.
- iOS: PASS — 133 tests across 31 suites.
- Request construction, credential gate, sandbox endpoint, collapse/TTL headers, invalid-token and bounded-retry classifications are covered.
