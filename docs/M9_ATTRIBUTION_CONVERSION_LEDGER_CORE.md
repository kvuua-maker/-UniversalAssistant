# M9 Attribution, Conversion and Commission Ledger Core

The server owns pseudonymous, expiring attribution records linked to the exact partner and immutable agreement version. Conversion transitions cover initiated, pending, confirmed, rejected, cancelled, full/partial refund, payable, paid and disputed states. External event IDs are idempotent.

Confirmed commission and refund adjustments use `Decimal` exclusively. Ledger entries and lifecycle audit events are append-only and retain transaction/agreement references, gross/basis/commission currencies and amounts, evidence, actor, event ID and timestamp. Refunds create negative proportional adjustments and cannot exceed original gross value; history is never deleted or rewritten.
