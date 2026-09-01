# M2 System-first Local Routing

- Calendar, Reminders, and Contacts commands route to their public Apple framework adapters.
- Ordinary shopping lists route to Reminders and are not duplicated in assistant storage.
- Notes route only to a system share/handoff path because unrestricted Apple Notes automation is not a public capability.
- Audio recording routes to the internal public-Apple-audio adapter.
- Unknown/unverified local actions are marked unavailable rather than pretending execution.

Verification: Development simulator suite passed 34 tests in 9 suites on 2026-09-01.
