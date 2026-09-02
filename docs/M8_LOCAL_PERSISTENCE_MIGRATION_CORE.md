# M8 Local Persistence Migration Core

- Requirements: 446, 705, 709–712, 745, 803.
- Existing `LocalStore` remains the single local persistence boundary and retains its backward-compatible raw save/load API.
- New records use an explicit positive schema version and atomically rewrite after a typed migration.
- Future-version data is rejected without mutation to preserve rollback/forward compatibility.
- Corrupt or undecodable data is moved to a uniquely named recoverable quarantine file rather than silently overwritten or deleted.
- Representative older-schema, corruption and future-schema paths are covered by tests.
- Local verification: 174 iOS tests across 43 suites and 29 backend tests across 7 suites passed on 2026-09-02.
- Exit state: `SUCCESS` at local E3.
