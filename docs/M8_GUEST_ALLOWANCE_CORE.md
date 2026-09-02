# M8 Guest Allowance Core

- Requirements: 1599–1607.
- A chargeable unit is one successfully completed independent task ID. Repeated completion steps and internal provider/module operations under the same ID are idempotent and cost zero additional actions.
- Guest registration is required at 15 completed tasks or seven elapsed days, whichever occurs first. Registered Free uses 30 tasks per seven-day cycle; Premium has no ordinary-action ceiling.
- Failed, cancelled, unresolved and merely planned operations are not recorded as completed tasks.
- The ledger uses app/account state only and introduces no device fingerprinting.
- Local verification: 171 iOS tests across 42 suites and 29 backend tests across 7 suites passed on 2026-09-02.
- Exit state: `SUCCESS` at local E3.
