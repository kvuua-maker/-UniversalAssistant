# M12 Gmail and Email Integration Core

Requirements MS-927–940. Local implementation status: VERIFIED_LOCAL. Authorized Gmail execution: READY_FOR_LIVE_VERIFICATION.

`EmailProvider` is provider-neutral. `GmailEmailProvider` uses the official Gmail REST host and bearer token supplied by the existing Keychain/OAuth boundary. It supports bounded Gmail-query search (including sender/recipient/subject/date/keywords through the provider query), selected raw RFC 2822 message retrieval, attachment bytes, drafts, confirmed replies, and confirmed label/archive/trash-style mutations. It validates paths, status codes and response schemas; provider failures never become success. Reply and destructive mutations make zero network calls without explicit confirmation.

Only query parameters needed for retrieval are sent, tokens are never persisted or logged by this client, and returned objects retain Gmail message/thread IDs for deterministic follow-up actions. Apple Mail inbox/history access is not claimed because third-party iOS apps have no public general Mail database API; compose/handoff remains the legitimate system boundary already represented by local actions.

Evidence: `GmailEmailProvider.swift`, `GmailEmailProviderTests.swift`, `ProviderAuthenticationBoundary.swift`. Five behavior tests cover official endpoint/query bounding, actual MIME retrieval, attachment decoding, confirmation gates and truthful HTTP failure. Real OAuth account operations are queued, not simulated.

Full regression on 2026-09-02: 251 iOS tests across 64 suites and 78 backend tests across 22 suites passed; canonical JSON and diff checks passed.
