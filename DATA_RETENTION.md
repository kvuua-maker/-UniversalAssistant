# Data Retention and Residency

The default enforceable policy is: operational logs 30 days, minimized analytics 90 days, backups 30 days, and deleted-account residuals at most 30 days after deletion. Active account data remains only while the account/product purpose exists. Business, agreement, conversion, financial, dispute and settlement history follows the applicable contract and legal retention policy; it has no invented universal expiry and may be erased only by an approved jurisdiction-specific rule. Legal holds are explicit and available only for data classes whose rule permits them.

`DataRetentionPolicy` validates that every known data class has exactly one rule and deterministically selects expired record IDs. Account-deletion age is measured from deletion rather than original creation. Analytics cannot use legal hold as a silent indefinite-retention mechanism. Backup expiry matches `DISASTER_RECOVERY.md`.

Production data residency is not assumed. Before activation, the owner/deployment operator must record the actual database, object-storage, backup, log, analytics, APNs, CloudKit and partner-provider regions; cross-border transfers; subprocessors; tenant/legal constraints; and deletion propagation. The selected region and legal retention overrides are configuration/compliance inputs, not hardcoded product facts.

Live verification consists of applying the policy to the deployed stores, proving deletion propagation and recording actual regions/subprocessors. Local policy validation and expiry behavior are fully automated and do not wait for that infrastructure.
