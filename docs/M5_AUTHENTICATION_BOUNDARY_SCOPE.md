# M5 Authentication Boundary — Requirement Scope Pack

- Task ID: `M5-AUTHENTICATION-BOUNDARY`
- Requirement IDs: 21–23, 38–49, 203, 211, 213–218, 280, 294, 385–388, 439, 441, 533–534, 655, 702–707, 755–761, 790–795, 814, 1472, 1476–1478, 1503.
- Exact capability: explicit provider access decision for public, OAuth, exact official authenticated handoff and unsupported paths; scoped token expiry/revocation; secure on-device token adapter.
- Selected path: useful V1 remains local-first without a mandatory UniversalAssistant account; capability-specific provider OAuth uses Keychain and exact official fallback.
- Integration depth: local E3 boundary; no provider OAuth client or production credential is claimed.
- Failure cases: missing/expired token, insufficient scope, invalid provider identity, homepage/generic sign-in destination, unsupported integration and disconnect cleanup.
- Security: no raw third-party password API; no production secrets in source; Keychain uses this-device-only protection; access results never expose token material.
- Stop condition: boundary and regression suites pass; checkpoint committed and pushed.

## Verification

- `xcodebuild ... test`: PASS — 129 tests across 30 suites.
- `swift test --package-path Backend`: PASS — 5 tests in 1 suite.
- Public/local-first access, scoped OAuth, expiry, disconnect cleanup and exact official fallback are covered; token material never leaves the credential store boundary.
