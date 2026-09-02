# Coordination Observability

`COORDINATION-OBSERVABILITY` extends the existing bounded `PerformanceRecorder`; it does not introduce a second analytics platform.

Each coordination run can record typed durations for intent resolution, plan creation, aggregate provider work, parallel critical path, first useful result, total completion, and bounded AI fallback. It also records provider call/cancellation counts and, only when a fallback was actually invoked, optional AI latency, input/output token counts, provider-reported cost metadata, and a typed fallback reason.

The observation contract intentionally has no fields for raw command text, provider payloads, URLs, account/user identifiers, credentials, or secrets. Counts and durations are validated, AI invocations are bounded to one, and the in-memory recorder drops oldest samples at its configured capacity.

Cost metadata is observational only, uses `Decimal`, preserves the provider-reported ISO-style currency code, and is absent when the provider does not supply it.
