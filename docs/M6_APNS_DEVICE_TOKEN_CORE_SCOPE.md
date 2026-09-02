# M6 APNs Device Token Core — Requirement Scope Pack

- Task ID: `M6-APNS-DEVICE-TOKEN-CORE`
- Requirement IDs: 21–23, 38–49, 385–387, 533–534, 641–655, 693–694, 699, 755–761, 790–795, 815.
- Exact capability: durable APNs token registration, refresh/replacement, environment isolation, multi-device lookup, provider invalidation, exact device removal and logout cleanup.
- Selected path: backend-local atomic registry contract; live APNs HTTP/2 delivery, signing key and deployment configuration are separate later gates.
- Failure cases: malformed token/identity, token rotation, token reassignment, sandbox/production collision, APNs invalidation, device removal, logout and process restart.
- Security: token values are never logged; snapshot uses atomic complete-file-protected writes; production storage/at-rest encryption remains deployment-specific.
- Stop condition: lifecycle tests and regressions pass; no live-delivery claim; checkpoint committed and pushed.

## Verification

- Backend: PASS — 14 tests across 3 suites.
- iOS: PASS — 133 tests across 31 suites.
- Restart, multi-device, rotation, environment isolation, invalidation, device removal and logout cleanup are covered.
