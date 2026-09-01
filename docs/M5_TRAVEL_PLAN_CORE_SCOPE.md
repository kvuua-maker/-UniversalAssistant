# M5 Travel Plan Core — Requirement Scope Pack

- Task ID: `M5-TRAVEL-PLAN-CORE`
- Requirement IDs: 21–23, 38–49, 102, 203, 217–223, 226, 288–302, 400–406, 603–607, 613–618, 628, 641–645, 790–795, 814, 1476–1478.
- Exact capability: rank evidence-backed intercity journeys against origin, destination, time, mode, transfer and budget constraints; compose optional station access, destination access, accommodation and weather context with explicit partial coverage.
- Selected path: provider-neutral local E3 composition over existing transport, ticket, hotel and weather evidence models.
- Feasibility: `PASS_SELECTED_PATH`; live journey search remains dependent on separate official provider adapters and capability gates.
- Integration depth: local E3 core only; no external booking or availability claim.
- Failure cases: missed arrival deadline, unsupported mode, stale evidence, scheduled-only inventory presented as live, unknown or mixed-currency total, missing access/hotel/weather context.
- Privacy: no passenger identity, account, payment or booking record is stored.
- Stop condition: deterministic composition and tests pass; missing context remains visible; checkpoint committed and pushed.

## Verification

- `xcodebuild ... test`: PASS — 124 tests across 29 suites.
- `swift test --package-path Backend`: PASS — 5 tests in 1 suite.
- Required accommodation cannot disappear from a budget; only fresh evidence and known mandatory fees contribute to a claimed total.
