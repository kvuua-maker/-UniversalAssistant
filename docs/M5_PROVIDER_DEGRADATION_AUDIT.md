# M5 Provider Degradation Audit — Requirement Scope Pack

- Task ID: `M5-PROVIDER-DEGRADATION-AUDIT`
- Requirement IDs: 21–23, 38–49, 203, 207–212, 288–302, 400–406, 603–607, 613–618, 628, 641–645, 790–795, 814, 1476–1478, 1504.
- Exact capability: reusable bounded concurrent provider fanout with stable aggregation, isolated timeout/error states and truthful complete/partial/failed coverage; concrete TicketProvider orchestration.
- Selected path: shared local E3 fanout primitive plus TicketProvider coordinator; existing hotel search already has equivalent bounded isolation and is not rewritten.
- Failure cases: timeout, provider error, all providers failed, duplicate provider identity, empty/unbounded provider set, invalid or stale returned offers.
- Truth boundary: only offers surviving the existing evidence-aware TicketEngine are returned; a provider failure never becomes an empty-success claim.
- Stop condition: focused and full regression suites pass; M5 cross-vertical audit documents no remaining local-core degradation gap.

## Verification

- `xcodebuild ... test`: PASS — 133 tests across 31 suites.
- `swift test --package-path Backend`: PASS — 5 tests in 1 suite.
- Hotel and TicketProvider fanout paths now both prove bounded timeout, isolated error, valid partial results and all-failed coverage; downstream evidence engines remain authoritative.
