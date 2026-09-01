# M6 Durable Job Core — Requirement Scope Pack

- Task ID: `M6-DURABLE-JOB-CORE`
- Requirement IDs: 21–23, 38–49, 406, 533–534, 641–655, 686–692, 699, 755–761, 790–795, 815.
- Exact capability: persistent proactive job queue model with logical deduplication/idempotency, expiration, source linking, cancellation, bounded exponential retry with jitter and dead-letter observability.
- Selected path: backend-local file-backed E3 reference implementation with atomic snapshots; production database/queue selection remains a later deployment gate.
- Failure cases: corrupt/invalid job, duplicate work, restart, expired job, transient repeated failure, maximum attempts, cancellation/reschedule and unknown job completion.
- Privacy: payload is opaque; dead-letter reason is bounded; no raw private command or secret logging is introduced.
- Stop condition: backend tests prove restart durability and lifecycle invariants; full iOS regression remains green; checkpoint committed and pushed.

## Verification

- `swift test --package-path Backend`: PASS — 9 tests across 2 suites.
- `xcodebuild ... test`: PASS — 133 tests across 31 suites.
- Restart persistence, queued/completed deduplication, bounded jittered retry, dead-letter, expiration, source linking and cancellation are covered.
