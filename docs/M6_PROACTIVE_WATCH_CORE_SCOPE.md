# M6 Proactive Watch Core — Requirement Scope Pack

- Task ID: `M6-PROACTIVE-WATCH-CORE`
- Requirement IDs: 238–246, 629–631, 633, 641–655, 685–692, 695–700, 790–795, 815.
- Exact capability: durable user-enabled traffic/weather/business/product/ticket watch rules, due-job scheduling, source linking, meaningful-change thresholds, fresh evidence and direct cancellation.
- Selected path: rule-based backend E3 core without paid AI; provider polling adapters remain capability-specific.
- Failure cases: invalid/expired rule, stale observation, immaterial change, duplicate schedule bucket and cancellation.
- Stop condition: backend lifecycle tests and iOS regression pass; checkpoint committed and pushed.

## Verification

- Backend: PASS — 27 tests across 6 suites.
- iOS: PASS — 133 tests across 31 suites.
- Restart scheduling, linked/deduplicable jobs, fresh evidence, accumulated meaningful change and direct cancellation are covered.
