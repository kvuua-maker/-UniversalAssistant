# M2 Contacts and Confirmed Aliases

- Contacts remain local and are queried on demand through public `CNContactStore` APIs.
- Authorization distinguishes not-determined, denied/restricted, full, and iOS 18 limited access.
- Multiple matches return an ambiguity result; no arbitrary fuzzy contact is selected.
- Confirmed multilingual aliases persist only as normalized alias → exact Contacts identifier.
- Alias replacement is explicit and deduplicated; invalid identifiers are rejected.
- All build configurations contain `NSContactsUsageDescription`.

Official API evidence verified 2026-09-01:

- https://developer.apple.com/documentation/contacts/accessing-the-contact-store
- https://developer.apple.com/documentation/contacts/cncontactstore

Verification: Development simulator suite passed 22 tests in 6 suites. Permission and real-contact behavior remain `DEVICE_TEST_REQUIRED`.
