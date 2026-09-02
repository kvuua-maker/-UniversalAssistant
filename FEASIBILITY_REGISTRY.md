# Feasibility Registry

This is the persistent per-capability path memory required by MS-1192–1231 and MS-1272–1306. A PASS closes discovery only for the exact capability/path. Reopening requires named new objective evidence. Provider-wide blanket passes are prohibited.

| Task ID | Exact capability/actions | Selected legitimate path | Official evidence checked | Access requirements | Proof result | State | Date/context |
|---|---|---|---|---|---|---|---|
| M0-IOS-BUILD | BUILD/RUN | Native SwiftUI/Xcode | Installed Apple SDK/toolchain | Xcode | Real simulator build/test | PASS_SELECTED_PATH (closed) | 2026-09-01, M0 |
| M0-LOCAL-PERSISTENCE | READ/WRITE/MIGRATE/RECOVER | Actor + atomic protected Codable files | Apple Foundation file APIs | None | E3 behavioral migration/recovery tests | PASS_SELECTED_PATH (closed) | 2026-09-01, M0–M10 |
| M2-CALENDAR-CRUD | AUTHORIZATION/READ/CREATE/UPDATE/DELETE | EventKit | M2_CALENDAR_SCOPE | Physical permission for E5 | E3 production path; E5 queued | PASS_SELECTED_PATH (closed) | 2026-09-01, M2 |
| M3-NAVIGATION | ROUTE/OPEN_EXACT_CONTEXT | MapKit + official map URLs | M3_ROUTE_NAVIGATION_SCOPE | Live route/device for E4/E5 | E3 adapter/routing; live queued | PASS_SELECTED_PATH (closed) | 2026-09-01, M3 |
| M4-SILPO-SEARCH | AUTHORIZATION/SEARCH/READ | Official Streamable HTTP MCP | M4_UA_RETAILER_SOURCE_MATRIX | Guest OAuth credentials | Production backend adapter + E3 tests; real query pending | NEEDS_OWNER_ACCESS_FOR_PROOF (open) | 2026-09-01, M4 |
| M4-ATB-STOCK | STOCK/PRICE | Exact official page only | M4_UA_RETAILER_SOURCE_MATRIX | No public API/feed verified | No live stock claim; exact-page fallback only | EXTERNAL_BLOCKED (open) | 2026-09-01, M4 |
| M5-UBER-QUOTE | QUOTE/ETA | Official provider API | M5_RIDE_PROVIDER_CAPABILITY_HANDOFF | Provider approval/OAuth scopes | Boundary implemented; real quote proof unavailable | NEEDS_OWNER_ACCESS_FOR_PROOF (open) | 2026-09-01, M5 |
| M5-UBER-HANDOFF | OPEN_EXACT_CONTEXT | Official route handoff | M5_RIDE_PROVIDER_CAPABILITY_HANDOFF | Public client ID | E3 context builder; device proof queued | NEEDS_OWNER_ACCESS_FOR_PROOF (open) | 2026-09-01, M5 |
| M12-GMAIL-READ | AUTHORIZATION/SEARCH/READ | Official Gmail REST API | M12_GMAIL_EMAIL_INTEGRATION_CORE | OAuth client/account/scopes | E3 production path; E4 queued | NEEDS_OWNER_ACCESS_FOR_PROOF (open) | 2026-09-02, M12 |
| M12-GMAIL-SEND | CREATE/SEND/UPDATE/DELETE | Official Gmail REST API with confirmation | M12_GMAIL_EMAIL_INTEGRATION_CORE | OAuth account + mutation scopes | E3 confirmation/failure tests; E4 queued | NEEDS_OWNER_ACCESS_FOR_PROOF (open) | 2026-09-02, M12 |
| M12-DIIA-PRIVATE-DOCS | READ private government documents | No unrelated-client path | M12_GOVERNMENT_LOCAL_SERVICES_CORE | Partner approval and user consent | Private access rejected; partner handoff retained | EXTERNAL_BLOCKED (open) | 2026-09-02, M12 |
| M12-CARPLAY | DISPLAY/ACTION | Category-specific entitlement/templates | M12_CARPLAY_SENSITIVE_DATA_POLICY | Owner category decision + Apple entitlement | Fail-closed E3 policy; E5 queued | NEEDS_OWNER_ACCESS_FOR_PROOF (open) | 2026-09-02, M12 |

## Path discipline audit

- One atomic task has one selected path; FeasibilityPathRegistry rejects a second active path and duplicate capability decision.
- Only PASS_SELECTED_PATH may be closed. A closed decision cannot reopen without recorded new evidence.
- Existing production modules use the proven native Swift/Swift Concurrency/Foundation stack; no parallel framework experiments or speculative rewrites were found.
- Open external decisions unlock only provider-neutral boundaries that remain valid regardless of credentials. They do not claim external integration or live success.
- Detailed capability matrices remain in PROVIDER_CAPABILITY_MATRIX.md, INTEGRATION_STATUS.md, and capability-specific scope documents.
