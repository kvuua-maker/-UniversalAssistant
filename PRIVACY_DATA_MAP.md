# Privacy Data Map

This map describes the implemented repository state. Provider/live deployment rows remain conditional until their corresponding item is VERIFIED_LIVE.

| Data | Storage/recipient | Purpose | Transfer | Retention/deletion |
|---|---|---|---|---|
| Typed/spoken command | Process memory | Parse and execute the current request | Sent only to the selected live provider when its capability requires the query; bounded AI is permitted only for unresolved interpretation | Input field clears after submit; not included in feedback |
| Wrong-result feedback | Protected local App Support JSON | Let the user mark an incorrect result | No implemented remote submission | Last 100 records; only diagnostic ID, category and time |
| Provider OAuth access token/scopes/expiry | iOS Keychain, this-device-only accessibility | Authorized provider access | Sent only to the matching provider | Deleted on disconnect; expired/revoked credentials require reauthorization |
| Contact aliases | Protected local App Support | Map a user-confirmed alias to an exact Contacts identifier | No | Replaceable/user-clearable |
| Action history/undo snapshot | Protected local App Support | Undo assistant-created reversible actions | No | Bounded to 100 records |
| Audio recordings | Protected App Support/Recordings | User-requested recording | No unless the user explicitly shares | Renameable and deletable by user |
| Apple Contacts/Calendar/Reminders | Apple system stores | Explicit local lookup or mutation | Governed by Apple frameworks and user permission | Managed by the user/system; minimal undo snapshots may be local |
| Location/query | Apple MapKit/WeatherKit or explicit route/provider handoff | Places, route and weather result | Only for the requested operation | No repository-owned history |
| Sync records | CloudSyncTransport boundary (intended CloudKit) | Optional cross-device synchronization | Only after authenticated account/sync activation | Tombstones and account deletion are coordinated; live propagation remains queued |
| APNs token and notification route | Protected backend durable store and Apple Push Notification service | Deliver opted-in proactive notifications | Token/payload to APNs over TLS | Invalidated on 410/logout/device removal; deployed retention verification queued |
| Partner attribution/conversion/ledger | Tenant-authorized backend durable domain | Auditable referral commission lifecycle | Partner/network evidence boundaries only | Append/adjust, subject to financial/legal retention |

No third-party analytics, advertising SDK, tracking domain, or production AI provider is linked in the current app target. See `DATA_PROCESSOR_INVENTORY.md`, `DATA_RETENTION.md`, and `PRIVACY_POLICY.md`.
