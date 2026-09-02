# M12 Universal Action Graph Core

Status: `VERIFIED_LOCAL`

Canonical requirements: MS-1069–MS-1076.

`UniversalActionGraph` provides reusable typed entities, actions, provider capabilities, verified results and next actions. Its entity taxonomy contains Person, Place, Product, Store, Email, Document, Event, Reminder, Ticket, Parcel, Appointment, Route and ProviderResult. Its action taxonomy contains SEARCH, OPEN, SHOW, CALL, MESSAGE, ROUTE, CREATE_EVENT, REMIND, COMPARE, BOOK, CANCEL, RESCHEDULE, TRACK and SHARE.

Every graph entity preserves provider/object provenance, verification, observed/expiry timestamps, typed relationships and allowed next actions. Composition rejects unknown, stale, unverified or kind-incompatible input. Consequential actions require explicit confirmation. It returns a typed invocation and never derives execution arguments from free text or invents provider facts.

Provider registration is capability-based, so another provider immediately participates in compatible graph flows without scenario-specific routing changes. Tests cover the canonical email/address/route/event, product/store/route, ticket/route/reminder, parcel/route/track and appointment/calendar/route/reminder building blocks, taxonomy completeness, freshness/truth, confirmation and provider extensibility.

Verification on 2026-09-02: targeted 5/5; full iOS 316 Swift Testing tests / 78 suites plus 5 Routine XCTest tests; backend 79 tests / 22 suites; zero failures.
