# M8 Account Deletion and Privacy Core

- Requirements: 317, 463, 537–538, 656, 706, 733, 817, 846–848, 1614–1615.
- Deletion runs typed independent cleanup contracts for proactive jobs, push tokens, provider connections, cloud data and the local account session.
- Partial cleanup never claims complete deletion; each failed category remains visible and retryable by the owning boundary.
- Export is portable, versioned, sorted JSON containing only assistant-owned records.
- The privacy manifest declares no tracking and currently no SDK-collected data or required-reason API category. It must be updated if production telemetry/SDK/API usage changes.
- External gate: live server deletion, OAuth provider revocation, CloudKit deletion and Apple account review behavior require configured production services and account/device evidence.
- Local verification: 183 iOS tests across 46 suites and 29 backend tests across 7 suites passed on 2026-09-02.
- Exit state: `SUCCESS` for the local E3 lifecycle contract.
