# Release and Rollback

CI is fail-closed: static privacy/localization checks, complete backend tests and an actual iOS simulator build/test must all pass before the staging job is eligible. Logs and commit/toolchain identity are retained as a bounded artifact. The staging job is manual and protected by the GitHub `staging` environment; it produces an identifiable release binary but does not claim deployment success.

Production deployment is intentionally not automatic. The owner must configure reviewed GitHub staging/production environments, deployment identity and the actual backend target before a deployment adapter can be validated. A production release requires explicit approval, a known-good artifact digest, backup/restore readiness, compatible migrations, health checks and a rollback operator.

Rollback order:

1. Stop promotion and preserve logs, artifact SHA and affected configuration version.
2. Disable the harmful feature through `PartnerRuntimePolicyStore.rollback(to:)` when configuration-only.
3. For code rollback, redeploy the last known-good immutable artifact.
4. Use only backward/forward-compatible migrations; never destructively reverse financial/audit history.
5. Run health, tenant-isolation, reconciliation, queue-idempotency and critical iOS smoke checks.
6. Record operator, timestamps, prior/new artifact SHA, config version and observed result.

The runtime policy store retains installed immutable versions and rejects rollback to an unknown version. Production deployment and rollback execution remain live verification until real GitHub Environments and a deployment target exist.
