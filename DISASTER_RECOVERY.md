# Disaster Recovery

## Policy and objectives

Server-side durable account, business, configuration, financial and operational state must be backed up at least hourly. The initial engineering objectives are an RPO of one hour and an RTO of four hours for critical backend services. Backups are retained for 30 days; longer financial retention belongs to the append-only primary ledger and jurisdiction-specific policy, not an unbounded backup archive.

Every archive is encrypted with AES-256-GCM using key material injected by the deployment secret manager, carries authenticated ciphertext plus a SHA-256 plaintext integrity digest, and expires according to the configured policy. Backup keys must never be stored in the repository, client binary, archive, or logs. Production storage identity, access policy, region and key rotation require deployment approval.

## Recovery order

1. Declare the incident, freeze unsafe writes and preserve audit evidence.
2. Restore deployment configuration and secret-manager access without copying secrets into tickets or logs.
3. Restore identity/tenant authorization and versioned commercial agreements.
4. Restore attribution, conversion, commission, reconciliation and settlement records.
5. Restore proactive jobs, APNs registrations and provider configuration.
6. Validate referential integrity, tenant isolation, monetary totals and queue idempotency.
7. Start read-only health checks, then bounded writes, then normal traffic.
8. Record the selected archive, observed recovery point/time, validation evidence and approver.

## Restore procedure

Select the newest non-expired archive that predates the incident. Fetch it through deployment-authorized storage, inject the matching active or recovery key, decrypt and authenticate it with `EncryptedBackupService.restore`, then restore into an isolated environment. Run backend tests and data-specific integrity/reconciliation checks before production promotion. Corrupt, expired, unauthenticated or wrong-key archives fail closed and must not replace durable state.

Automated local restore tests prove encryption, exact round-trip, expiry, retention and fail-closed corruption behavior. A scheduled production backup job, access-control review and isolated infrastructure restore drill require deployed storage/KMS and are tracked separately as live verification; they do not block other engineering work.

## Manual dependencies

The operator supplies the approved storage service, region, service identity, KMS key lifecycle, schedule, alert destination and production database snapshot mechanism. Legal/finance owners approve any jurisdiction-specific retention extension. Incident command authorizes write freeze, archive selection and production cutover.
