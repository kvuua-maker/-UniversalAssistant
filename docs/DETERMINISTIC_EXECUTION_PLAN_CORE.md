# Deterministic Execution Plan Core

- Reuses `StructuredCommand`, existing command parsing, provider modules and Swift concurrency boundaries.
- Produces typed intent, constraints, capabilities, dependencies, parallel groups and completion step; it never stores an execution contract as free text.
- Known simple commands use a two-step direct-action/compose fast path with zero AI invocations.
- Travel plans resolve date and location, use Calendar as a hard prerequisite for return-sensitive transport/hotel work, and expose Weather + Transport + Hotel as one independent parallel group.
- Invalid/cyclic plans fail deterministically. Unresolved commands remain explicitly unresolved and do not invoke AI inside the planner.
- Local verification: 188 iOS tests across 47 suites and 29 backend tests across 7 suites passed on 2026-09-02.
- Exit state: `SUCCESS` at local E3.
