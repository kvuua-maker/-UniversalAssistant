# M2 Calendar Vertical

- Public EventKit `requestFullAccessToEvents` path for iOS 17+; deprecated generic access is not used.
- Create, bounded-range query, update, and single-event delete operate inside one actor-owned `EKEventStore`.
- Drafts reject empty titles and invalid time ranges.
- Mutations report success only after authoritative EventKit read-back.
- Calendar create/update records have capability-specific undo behavior using exact identifiers and encoded prior snapshots.
- All configurations include `NSCalendarsFullAccessUsageDescription`.

Official API evidence verified 2026-09-01:

- https://developer.apple.com/documentation/eventkit/accessing-the-event-store
- https://developer.apple.com/documentation/eventkit/ekeventstore
- https://developer.apple.com/documentation/bundleresources/information-property-list/nscalendarsfullaccessusagedescription

Verification: Development simulator suite passed 26 tests in 7 suites. Permission and real create/update/delete/read-back remain `DEVICE_TEST_REQUIRED`.
