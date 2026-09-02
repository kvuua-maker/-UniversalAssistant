# M9 Fraud and Abuse Controls Core

The backend evaluates typed, policy-versioned signals for duplicate attribution/transactions, webhook replay, suspected self-referral, excessive velocity/refunds and impossible commission-over-gross values. Duplicate/replay evidence is rejected; other anomalies require review and are not treated as automatic guilt.

Every assessment is auditable with partner, attribution, signals, disposition, policy version and timestamp. The engine does not delete or rewrite conversions, ledger entries, disputes or refunds. Thresholds are supplied by configuration rather than hardcoded commercial policy.
