# M9 Reconciliation and Settlement-State Core

Reconciliation compares partner-scoped internal conversion/commission history with partner or network report lines and emits findings for missing, duplicate, amount, currency, status and unexpected-refund discrepancies. It is read-only: findings never rewrite financial history.

Settlement tracking is a state/reference boundary, not a bank or payment processor. A valid commission can be marked `PAYABLE` with settlement, invoice/tax metadata and evidence references. It becomes `PAID` only through a separate confirmation carrying its own evidence and actor, with both states retained in the audit trail.
