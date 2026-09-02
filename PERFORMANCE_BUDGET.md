# Performance Budget

Canonical metrics: cold launch, warm launch, Action Button → listening, end-of-speech → local parse, first network result, normal RAM, and selected CPU/battery checks.

Targets are not invented before measurement. A release budget record must include the supported device/OS/build/environment reference, measured baseline, unit, agreed maximum, sample method/count and date. Missing or invalid measurements produce `unavailable` and cannot pass the release gate; values above an agreed maximum fail it unless an explicit reviewed justification is recorded.

Current local baseline evidence:

- Local parser regression fixture: 1,000 representative parses complete within the existing two-second simulator/host guard. This is a regression fixture, not a device release budget.
- Provider fan-out and deterministic coordination have bounded timeout/concurrency tests and first-useful-result telemetry.
- Cold/warm launch, Action Button → listening, normal RAM and CPU/battery release baselines remain real-device measurements for M11; no fabricated numeric target is recorded here.
- Local iPhone search runs sources concurrently, caps individual Photos fetch candidates at 200 and final results at 10. Actual supported-iPhone latency remains queued as a measured device baseline; no simulator number is presented as a device budget.

`PerformanceBudgetEvaluator` consumes measured `Decimal` values and explicit budgets. Every canonical metric is typed, and the aggregate release gate fails closed on a regression or missing measurement.
