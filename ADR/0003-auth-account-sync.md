# ADR 0003: Authentication, account and sync

- Date: 2026-09-02
- Version: 1
- Context: Core local commands must work without registration while optional sync/subscription/provider capabilities need verified identity and revocable credentials.
- Decision: Keep a guest/local-first core; use verified Sign in with Apple identity for account capabilities, Keychain for provider OAuth credentials, StoreKit for entitlement truth, and a local-primary CloudSyncTransport boundary with deterministic conflict/tombstone reconciliation.
- Alternatives considered: Mandatory account launch was rejected because it blocks local utility; storing OAuth tokens in app files was rejected; server-authoritative-only sync was rejected because outages must not break local use.
- Consequences: Missing/revoked credentials degrade to reauthorization or local-only use. Live Apple/provider verification remains credential/device dependent, while all local state machines are testable.
