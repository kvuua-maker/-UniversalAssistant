# M8 Local Acceptance

- Milestone: M8 Accounts, Sync and Monetization.
- Exit state: `SUCCESS` at local E3 on 2026-09-02.
- Verified baseline: 183 iOS tests across 46 suites and 29 backend tests across 7 suites.
- Accepted cores: account/auth decision, Sign in with Apple session boundary, guest/free allowance, versioned local migrations, local-primary sync reconciliation, StoreKit entitlement truth, account deletion/export and privacy manifest.
- External gates remain explicit: Apple authentication keys/backend exchange, CloudKit container/provisioning/multi-device runs, App Store Connect products/sandbox/server notifications, and live server/provider deletion.
- No live external capability is claimed from simulator evidence. Local commands remain useful without cloud or AI.
- Owner action required now: none for independent local work.
