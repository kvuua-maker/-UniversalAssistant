# M12 Connected Accounts Hub Core

Requirements MS-921–926. Status: VERIFIED_LOCAL.

`ConnectedAccountsHub` composes the existing `ProviderAuthenticationBoundary` and Keychain credential store rather than duplicating OAuth. Provider contracts declare exact minimum scopes. Connection rejects credentials containing unrequested scopes, health distinguishes connected/expiry, reauthorization, sign-in, unavailable and isolated provider errors, and disconnect invokes provider revocation before local deletion when supported.

Only non-secret display/capability/health metadata is persisted with complete file protection; access tokens remain in the existing device-only Keychain boundary. Restore discards retired/unknown provider metadata. One account's disconnect or health failure does not mutate another account.

Evidence: `ConnectedAccountsHub.swift`, `ProviderAuthenticationBoundary.swift`, and `ConnectedAccountsHubTests.swift`. Four behavioral tests verify exact-scope enforcement, expiry health, revoke-before-delete isolation and restart restoration. Live provider authorization remains capability-specific and will be queued by each provider implementation rather than claimed by this core.

Full regression on 2026-09-02: 246 iOS tests across 63 suites and 78 backend tests across 22 suites passed; canonical JSON and diff checks passed.
