# M2 ActionHistory / Undo

- Bounded, persisted history contains only assistant-created or assistant-modified reversible action records.
- Undo targets the latest completed record and requires a capability-specific handler.
- A record becomes `undone` only after handler success; failure restores availability and propagates the error.
- Interrupted `undoing` state is recovered as available but never auto-executed after launch.
- Empty external identifiers are rejected so undo cannot target an unknown system object.

Verification: Development simulator suite passed 18 tests in 5 suites on 2026-09-01. Real Calendar/Reminders undo remains gated on their respective verticals and device tests.
