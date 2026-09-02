# M8 Account/Auth Decision

- Requirements: 702–708, 817, 1597–1605, 1615.
- Decision: an account is required for sync, server watches, entitlements and recovery, but the app launches in useful local-first Guest mode without a registration wall.
- Primary authentication: Sign in with Apple; no invented password or recovery system.
- Launch allowance: Guest has 15 completed tasks or 7 days; registered Free has 30 completed tasks per 7-day cycle. One coherent compound task counts once.
- Merge: preserve local assistant-owned data and deduplicate by stable identifier when linking an account.
- Logout: preserve accessible user-owned local data while unregistering push, cancelling account-scoped jobs and revoking provider tokens.
- Next implementation: Sign in with Apple session boundary and deterministic guest allowance accounting.
- Local verification: 164 iOS tests across 40 suites and 29 backend tests across 7 suites passed on 2026-09-02.
- Exit state: `SUCCESS` at local E3.
