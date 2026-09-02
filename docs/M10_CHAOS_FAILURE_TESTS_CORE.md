# M10 Chaos / Failure Tests Core

The existing bounded provider fan-out remains the shared failure-isolation primitive; this block does not add a parallel orchestration framework. Parent-command cancellation is now propagated instead of being misreported as a provider failure, so an obsolete command cannot publish a stale aggregate.

The executable chaos gate covers a provider that never responds, a response that becomes late after timeout cancellation, simultaneous backend/network-provider failure with a verified local partial result, and a new command replacing cancelled old work. Existing suites separately cover suspicious GPS, optional-AI failure, missing third-party apps, durable retry/dead-letter behavior, webhook replay/idempotency and provider health degradation.

All injected failures are deterministic local fixtures. No live provider facts are synthesized, retries remain bounded, and failure reasons expose neither secrets nor personal command content.
