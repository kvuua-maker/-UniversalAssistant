# ADR 0004: Backend, durable queue and notifications

- Date: 2026-09-02
- Version: 1
- Context: Proactive work and APNs delivery must survive restart, deduplicate logical work, expire safely and isolate provider failures.
- Decision: Use a dependency-free Swift 6 backend boundary with actor-isolated, file-backed reference persistence; a durable job state machine with bounded retry/dead-letter; explicit notification policy; environment-separated APNs tokens; and injected transport/authorization.
- Alternatives considered: In-process timers alone were rejected as non-durable; blind retry was rejected; embedding APNs/provider secrets in the app was rejected. A third-party queue is deferred until a deployment workload justifies one.
- Consequences: Local behavior is production-shaped and restart-tested. The selected production database/queue, KMS and host remain deployment configuration and must pass live restore/failure tests.
