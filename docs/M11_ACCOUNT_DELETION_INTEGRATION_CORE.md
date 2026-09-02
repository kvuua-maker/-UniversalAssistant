# M11 Account Deletion Integration Core

Requirements MS-846–MS-849. Status: VERIFIED_LOCAL.

| ID | Evidence |
| --- | --- |
| MS-846 | `AssistantOwnedDataExport` emits deterministic portable sorted JSON containing assistant-owned `SyncRecord` values; behavior is decoded/asserted by `AccountDataLifecycleTests` |
| MS-847 | Backend `AccountDeletionCleanupService` concurrently cancels the account's durable proactive jobs, removes its APNs registrations and revokes/deletes its provider connections; it preserves other accounts and reports each failure without fake success |
| MS-848 | `ProviderAuthenticationBoundary.disconnect(_:)` invokes the injected production OAuth revocation boundary before deleting the Keychain credential when the provider supports revocation; behavior is verified end-to-end with stored credential/readback |
| MS-849 | Existing backend tenant authorization enforces server-side partner isolation and audits denied reads/writes; `PartnerTenantAuthorizationTests` cover cross-tenant dashboard/finance access |

Verification (2026-09-02): 9 targeted iOS account/export/OAuth tests passed; full iOS regression passed 231 tests in 58 suites; full backend regression passed 78 tests in 22 suites, including real file-backed job and APNs cleanup. Provider-specific live OAuth revocation remains covered by the existing provider-contract queue item because it requires approved credentials; all local implementation is complete.
