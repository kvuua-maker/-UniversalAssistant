# M1 Interaction Safety

- Deterministic, tested interaction decisions select clarification, direct action, compact acknowledgement, visual selection, or confirmation.
- Ambiguous commands never guess; emergency, destructive, and materially consequential paths require confirmation.
- Search/comparison commands select visual-result UI; clear low-risk commands select the direct pattern.
- Parsing no longer claims that an external action completed: until an executor provides authoritative success, UI says only that the command was recognized.

Verification: Development simulator suite passed 14 tests in 4 suites on 2026-09-01.
