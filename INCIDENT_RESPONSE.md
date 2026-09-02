# Incident Response

## Detection and severity

`OperationalIncidentMonitor` independently tracks backend, persistent queue, APNs, database and provider health. A critical failure alerts immediately; repeated transient failures cross a configured threshold. Each incident emits one privacy-safe diagnostic ID, suppresses duplicate alerts, exposes a concise degradation status key and emits a matching recovery event.

## Response playbooks

- Provider outage: mark only the affected dependency degraded, stop wasteful calls, preserve verified alternatives and never fabricate results.
- Backend/database outage: stop unsafe writes, preserve evidence, validate backups, restore in the order defined by `DISASTER_RECOVERY.md`, then reopen bounded traffic.
- Persistent queue/APNs failure: suspend duplicate delivery, retain idempotency keys, inspect dead letters and revoke invalid tokens.
- Security issue: contain access, rotate affected credentials, preserve audit history, assess disclosure duties and deploy only a reviewed fix.
- Bad release: stop promotion and follow `ROLLBACK.md` using immutable artifact/config identity.
- False business data: mark data stale/unavailable, stop monetizable handoffs where trust is affected, preserve source evidence and require revalidation.
- Notification spam: disable the implicated watch/rule/collapse path, preserve bounded delivery evidence and verify user preference enforcement.

## Communication and evidence

Users receive only a short localized degradation message and diagnostic ID, never raw logs or provider payloads. Feedback records contain only the diagnostic ID, a bounded category and timestamp. Operators record incident owner, start/end, affected dependency, artifact/config versions, actions, evidence, user impact and recovery validation.

The production alert destination, paging schedule, support contact and public status channel require owner-selected operational accounts. Local alert generation, thresholding, deduplication, recovery and minimized feedback are executable and tested; delivery through those live channels is tracked separately.
