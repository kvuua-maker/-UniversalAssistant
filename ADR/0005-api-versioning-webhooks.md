# ADR 0005: API contracts, partner webhooks and versioning

- Date: 2026-09-02
- Version: 1
- Context: Partner and client integrations require stable schemas, replay safety, backward compatibility and auditable financial events.
- Decision: Use typed Codable contracts with explicit schema versions, contiguous staging migrations, HMAC-signed bounded webhooks, mandatory durable event idempotency, versioned commercial agreements and append-or-adjust financial history. Support the current iOS minor line plus two prior minor lines by default; forced updates require a typed critical compatibility, security or legal reason.
- Alternatives considered: Free-text payload contracts, process-local dedupe and retroactive agreement rewrites were rejected. Convenience-only forced updates were rejected.
- Consequences: Breaking schema changes require staged migration/compatibility evidence. Provider-specific formats remain behind normalized adapters and cannot leak into UI/domain logic.
