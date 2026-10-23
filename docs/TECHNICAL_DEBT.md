# Technical Debt Register

Each entry records a deliberately deferred, *tracked* deviation from the
canonical engineering standard. Nothing here is "done"; entries are closed only
by evidence, in the same spirit as the ZERO-OMISSION policy.

## TD-001 — Swift strict concurrency relaxed for Development

- **Status:** OPEN (accepted 2026-10-24, owner decision)
- **Change:** `SWIFT_STRICT_CONCURRENCY = minimal` in `Config/Development.xcconfig`.
- **Why:** the iOS target had never been compiled under Swift 6 strict
  concurrency. Fixing it surfaced a long tail of `Sendable`/isolation errors
  (`UNNotificationSettings`, the generic `postAttested` response, HEOS parsing)
  that each cost a full macOS CI cycle to discover. A buildable app was needed
  to validate base behaviour first.
- **Scope of the deviation:** compiler diagnostics only. No runtime behaviour,
  no capability, no privacy or data-flow contract is relaxed.
- **Exit criteria (all must hold):**
  1. `SWIFT_STRICT_CONCURRENCY = complete` in Development, Staging *and*
     Production.
  2. `xcodebuild test` green on macOS with that setting.
  3. Concurrency fixes landed module by module (Voice → Diagnostics → Audio →
     Core → Integrations → Commerce), each with its own green CI run.
  4. No `nonisolated(unsafe)` added purely to silence a diagnostic.
- **Rollback cost:** one line per configuration plus the accumulated fixes.
- **Owner action required:** none until the TestFlight build is validated.

## Trust boundary

Relaxing concurrency checking does **not** permit: data races in production
paths, `@unchecked Sendable` on mutable state, or unchecked global mutable
state. Any such construct found while completing TD-001 is a defect, not a
shortcut.
