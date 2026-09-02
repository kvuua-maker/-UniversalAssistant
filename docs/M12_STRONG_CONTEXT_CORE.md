# M12 Strong Context Core

Status: `VERIFIED_LOCAL`

Canonical requirements: MS-1064–MS-1068.

`CurrentContext` is now a local, Codable structured context rather than a last-message list. It carries current time, accuracy-validated location, active route/destination, next event, current task, typed result entities, selected entity, connected-service state, explicit preferences, and exact source/object/timestamp provenance.

Every stored provider object has its own expiry. Global and object-level expiry prevent stale follow-ups; manual reset clears all fields. `externalPayload` is deny-by-default and emits only explicitly allowlisted identifiers, never the full local context.

Deterministic typed follow-ups cover the canonical cheaper-result, navigate-there, call-them, reschedule-one-hour and pharmacy-along-route cases. A missing, stale or insufficiently identified object returns `unresolved` rather than guessing.

Evidence: `StrongCurrentContextTests` verifies all canonical fields/provenance, five follow-ups, stale rejection, allowlisted external disclosure, manual/automatic reset, and invalid location rejection. Existing `LocalCommandEngineTests.contextResolvesAndExpires` remains green for compatibility. Full regression on 2026-09-02: 311 Swift Testing tests / 77 suites plus 5 Routine XCTest tests; backend 79 tests / 22 suites; zero failures.
