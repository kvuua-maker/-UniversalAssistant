# Performance Budget

Targets are evidence-driven and will be tightened after physical-device baselines. M1 records bounded in-memory samples only; no raw command text is retained.

| Metric | Current evidence | Provisional regression rule |
|---|---|---|
| Local structured parse | 1,000 representative parses: 0.189 s on designated Mac/Simulator test run, 2026-09-01 | Under 2 seconds in CI/Simulator; physical per-command baseline pending |
| Cold/warm launch | Simulator launch observed | Measure on supported iPhone before setting release threshold |
| Voice invocation → listening | System path implemented | Physical iPhone baseline pending VOICE-001/002 |
| First commerce result/card/images | M4 | Establish per-provider and weak-network baselines before thresholds |

Commerce addendum requires independent startup, first useful result, scrolling, memory, image, cancellation and timeout budgets; Commerce modules remain unloaded at launch.
