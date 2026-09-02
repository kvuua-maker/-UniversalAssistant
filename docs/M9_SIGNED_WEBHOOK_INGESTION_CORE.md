# M9 Signed Webhook Ingestion Core

Partner callbacks are accepted only inside a bounded replay window after HMAC-SHA256 verification with a server-side credential selected by partner and key ID. The decoded envelope is schema-version validated before its event ID is committed to the partner-scoped idempotency set.

Credentials support overlap during rotation and explicit revocation; secrets and signatures are absent from the audit model. Duplicate delivery returns a typed duplicate outcome and cannot create a second downstream conversion or commission. Invalid signatures, stale timestamps, unknown/revoked credentials and invalid schemas fail closed.
