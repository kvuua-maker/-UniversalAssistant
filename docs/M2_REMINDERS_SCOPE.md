# M2 Reminders Vertical

- Public EventKit full-access Reminders API, isolated in its own actor-owned store.
- Create, incomplete-query, update/complete, and delete paths validate input and use exact identifiers.
- Save/remove success requires authoritative EventKit read-back.
- Fetch returns Sendable snapshots rather than retaining EventKit objects outside the adapter.
- Create/update undo uses exact identifiers and encoded prior snapshots.
- All configurations include `NSRemindersFullAccessUsageDescription`.

Official API evidence: https://developer.apple.com/documentation/eventkit/accessing-the-event-store and https://developer.apple.com/documentation/bundleresources/information-property-list/nsremindersfullaccessusagedescription (verified 2026-09-01).

Verification: Development simulator suite passed 30 tests in 8 suites. Real permission and mutation/read-back remain `DEVICE_TEST_REQUIRED`.
