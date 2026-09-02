# M8 Sign in with Apple Core

- Requirements: 704, 707, 817, 1597–1598.
- Identity tokens and authorization codes are accepted only through a backend verifier contract; the client never treats decoded unverified claims as authentication.
- The stable Apple subject is the account identifier. Revoked, missing, transferred or unknown credential state requires reauthentication.
- Sign-out removes the local authenticated session; remote cleanup follows the separately defined logout policy.
- Entitlement is configured for all build configurations.
- Device/backend gate: live Apple authorization UI, server-side token/code verification, Services ID/key configuration and credential-state behavior require owner Apple capability configuration and physical-device testing.
- Local verification: 167 iOS tests across 41 suites and 29 backend tests across 7 suites passed on 2026-09-02.
- Exit state: `SUCCESS` for the bounded local E3 session contract.
